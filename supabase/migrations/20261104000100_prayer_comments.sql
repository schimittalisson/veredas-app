-- =========================================================================
-- Comentários no mural: exclusão, proteção do texto e denúncia
--
-- `prayer_comments` existe desde a migration 0400, com policies e sync, mas
-- nunca teve tela: o cartão da oração mostrava "0 comentários" e não havia
-- como comentar. Ao ganhar tela, o comentário passa a ser conteúdo criado por
-- usuário e entra no escopo da Guideline 1.2 da App Store, como o pedido de
-- oração já entrou na migration 20260930000100. Esta migration fecha as três
-- lacunas que a tabela tinha para isso.
--
-- -------------------------------------------------------------------------
-- 1. Excluir comentário com RETURNING
-- -------------------------------------------------------------------------
--
-- O app apaga com `update ... set deleted_at ... returning` (o `.select()`
-- do outbox, que é como ele detecta a negação silenciosa do RLS). O RETURNING
-- exige que a linha NOVA passe na policy de SELECT, e a policy filtrava
-- `deleted_at is null`: toda exclusão voltaria 42501 e o comentário voltaria
-- à tela com o banner de erro. É exatamente o bug que a migration
-- 20260930000200 corrigiu em `prayer_posts`.
--
-- A policy passa a deixar o autor e o admin lerem a linha apagada. Os outros
-- continuam sem vê-la, e o app descarta a lápide no pull.
--
-- -------------------------------------------------------------------------
-- 2. O admin apaga o comentário alheio, mas não o reescreve
-- -------------------------------------------------------------------------
--
-- Mesma decisão e mesmo mecanismo de `protect_prayer_post_content`
-- (migration 20260930000300): RLS não distingue coluna, então o UPDATE que o
-- admin precisa para apagar também permitiria mudar o texto.
--
-- -------------------------------------------------------------------------
-- 3. Denúncia de comentário
-- -------------------------------------------------------------------------
--
-- `content_reports` ganha `comment_id` e a cópia do comentário
-- (`comment_body`, `comment_author_id`), tirada pelo servidor pelo mesmo
-- motivo da cópia do post: o admin precisa ver o que foi denunciado, não o
-- que está lá agora.
--
-- `post_id` continua obrigatório e, numa denúncia de comentário, é o post em
-- que o comentário está — preenchido pelo trigger a partir do comentário, não
-- do que o app mandar. A cópia do post vem junto e dá contexto ao admin.
--
-- O índice único passa a ser dois: uma denúncia por pessoa por post, e uma
-- por pessoa por comentário. Com o índice antigo, quem denunciou um
-- comentário não poderia denunciar o post, nem outro comentário do mesmo post.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. SELECT deixa o autor e o admin verem a lápide
-- -------------------------------------------------------------------------

drop policy if exists prayer_comments_select on public.prayer_comments;
create policy prayer_comments_select on public.prayer_comments
  for select to authenticated
  using (
    public.is_member()
    and (deleted_at is null or author_id = auth.uid() or public.is_admin())
  );

-- -------------------------------------------------------------------------
-- 2. Só o autor muda o texto
-- -------------------------------------------------------------------------

create or replace function public.protect_prayer_comment_content()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Sem auth.uid(): SQL Editor, migration ou RPC interno (o
  -- `delete_own_account` apaga os comentários da pessoa por aqui).
  if auth.uid() is null or old.author_id = auth.uid() then
    return new;
  end if;

  if new.body      is distinct from old.body
     or new.post_id   is distinct from old.post_id
     or new.author_id is distinct from old.author_id then
    raise exception 'FORBIDDEN_COMMENT_EDIT';
  end if;

  return new;
end;
$$;

drop trigger if exists prayer_comments_protect_content on public.prayer_comments;
create trigger prayer_comments_protect_content
  before update on public.prayer_comments
  for each row execute function public.protect_prayer_comment_content();

-- -------------------------------------------------------------------------
-- 3. Denúncia de comentário
-- -------------------------------------------------------------------------

alter table public.content_reports
  add column if not exists comment_id uuid
    references public.prayer_comments(id) on delete cascade,
  add column if not exists comment_body text,
  add column if not exists comment_author_id uuid;

drop index if exists public.content_reports_unique_idx;
create unique index if not exists content_reports_post_unique_idx
  on public.content_reports (reporter_id, post_id)
  where comment_id is null;
create unique index if not exists content_reports_comment_unique_idx
  on public.content_reports (reporter_id, comment_id)
  where comment_id is not null;

-- Substitui a versão da migration 20260930000100. O que mudou: o ramo do
-- comentário no começo. O resto é idêntico.
create or replace function public.fill_report_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_post    public.prayer_posts;
  v_comment public.prayer_comments;
begin
  if new.comment_id is not null then
    select * into v_comment
      from public.prayer_comments where id = new.comment_id;
    -- O definer lê por cima do RLS: quem garante que só se denuncia
    -- comentário vivo é esta checagem.
    if v_comment.id is null or v_comment.deleted_at is not null then
      raise exception 'COMMENT_NOT_FOUND';
    end if;
    new.post_id           := v_comment.post_id;
    new.comment_body      := v_comment.body;
    new.comment_author_id := v_comment.author_id;
  else
    new.comment_body      := null;
    new.comment_author_id := null;
  end if;

  select * into v_post from public.prayer_posts where id = new.post_id;
  if v_post.id is null or v_post.deleted_at is not null then
    raise exception 'POST_NOT_FOUND';
  end if;

  new.post_title        := v_post.title;
  new.post_body         := v_post.body;
  new.post_author_id    := v_post.author_id;
  new.post_is_anonymous := v_post.is_anonymous;
  new.resolved_at := null;
  new.resolved_by := null;
  return new;
end;
$$;

-- Comentário apagado resolve as denúncias dele — mesmo raciocínio de
-- `resolve_reports_of_deleted_post`: apagar é a ação mais comum do admin
-- sobre a denúncia, e ela não deve ficar na fila apontando para o nada.
create or replace function public.resolve_reports_of_deleted_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    update public.content_reports
       set resolved_at = now(),
           resolved_by = auth.uid()
     where comment_id = new.id
       and resolved_at is null;
  end if;
  return new;
end;
$$;

drop trigger if exists prayer_comments_resolve_reports on public.prayer_comments;
create trigger prayer_comments_resolve_reports
  after update of deleted_at on public.prayer_comments
  for each row execute function public.resolve_reports_of_deleted_comment();
