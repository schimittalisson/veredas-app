-- =========================================================================
-- Moderação do mural: denúncia de pedido de oração e bloqueio de usuário
--
-- Exigência da App Store (Guideline 1.2): app com conteúdo criado por usuários
-- precisa de (a) termos com tolerância zero, (b) um jeito de denunciar
-- conteúdo, (c) um jeito de bloquear quem abusa e (d) alguém que aja sobre as
-- denúncias. Os termos moram em TERMOS.md e no aceite do cadastro; esta
-- migration cobre (b), (c) e o apoio a (d).
--
-- O conteúdo sujeito a isso é só `prayer_posts`: `prayer_comments` existe no
-- banco mas não tem tela, e os avisos da tela Início são escritos por admin.
-- Se os comentários ganharem tela, ganham também uma coluna `comment_id` aqui.
--
-- -------------------------------------------------------------------------
-- Por que a denúncia guarda uma cópia do post
-- -------------------------------------------------------------------------
--
-- `post_title`, `post_body`, `post_author_id` e `post_is_anonymous` são
-- preenchidos pelo trigger `fill_report_snapshot`, a partir da linha real —
-- nunca pelo que o app manda. Duas razões:
--
-- 1. O autor pode editar o pedido depois de denunciado. Sem a cópia, o admin
--    abriria a denúncia e veria o texto já "limpo".
-- 2. O admin que bloqueou o autor não vê mais o post no feed (a view filtra),
--    e mesmo assim precisa conseguir moderar a denúncia.
--
-- -------------------------------------------------------------------------
-- Anonimato
-- -------------------------------------------------------------------------
--
-- O app não oferece "bloquear" em pedido anônimo: a lista de bloqueados
-- mostraria o nome de quem escreveu, e o anonimato acabaria ali. Pedido
-- anônimo se denuncia, e o admin o remove. Pelo mesmo motivo a tela de
-- denúncias não mostra o autor de um pedido anônimo — `post_author_id` fica
-- guardado só para o caso de a liderança precisar agir pelo banco.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Tabelas
-- -------------------------------------------------------------------------

create table public.content_reports (
  id                uuid primary key default gen_random_uuid(),
  reporter_id       uuid not null references public.profiles(id) on delete cascade,
  post_id           uuid not null references public.prayer_posts(id) on delete cascade,
  reason            text not null check (reason in ('offensive', 'spam', 'other')),
  post_title        text,
  post_body         text,
  post_author_id    uuid,
  post_is_anonymous boolean not null default false,
  resolved_at       timestamptz,
  resolved_by       uuid references public.profiles(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- Uma denúncia por pessoa por post. Tocar duas vezes não gera duas.
create unique index content_reports_unique_idx
  on public.content_reports (reporter_id, post_id);
create index content_reports_pending_idx
  on public.content_reports (created_at) where resolved_at is null;

create trigger content_reports_touch_updated_at
  before update on public.content_reports
  for each row execute function public.touch_updated_at();

-- Sem `id` próprio: a identidade do bloqueio é o par. E sem `deleted_at`:
-- desbloquear é DELETE físico, como `prayer_interactions` — o app sincroniza
-- esta tabela por substituição total, que enxerga a remoção.
create table public.user_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- -------------------------------------------------------------------------
-- 2. Cópia do post na denúncia
-- -------------------------------------------------------------------------

-- security definer porque o post pode ser de alguém que o denunciante não
-- enxerga mais por algum motivo; a leitura é só da linha denunciada.
create or replace function public.fill_report_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_post public.prayer_posts;
begin
  select * into v_post from public.prayer_posts where id = new.post_id;
  -- O definer lê por cima do RLS, então quem garante que só se denuncia post
  -- vivo é esta checagem, e não a policy de prayer_posts.
  if v_post.id is null or v_post.deleted_at is not null then
    raise exception 'POST_NOT_FOUND';
  end if;

  new.post_title        := v_post.title;
  new.post_body         := v_post.body;
  new.post_author_id    := v_post.author_id;
  new.post_is_anonymous := v_post.is_anonymous;
  -- Quem denuncia não resolve a própria denúncia na criação.
  new.resolved_at := null;
  new.resolved_by := null;
  return new;
end;
$$;

create trigger content_reports_fill_snapshot
  before insert on public.content_reports
  for each row execute function public.fill_report_snapshot();

-- -------------------------------------------------------------------------
-- 3. Post removido resolve as denúncias dele
-- -------------------------------------------------------------------------
--
-- A ação mais comum do admin sobre uma denúncia é apagar o post. Sem isto, a
-- denúncia ficaria na fila apontando para um post que já não existe, e o
-- admin teria de resolvê-la de novo, à mão.

create or replace function public.resolve_reports_of_deleted_post()
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
     where post_id = new.id
       and resolved_at is null;
  end if;
  return new;
end;
$$;

create trigger prayer_posts_resolve_reports
  after update of deleted_at on public.prayer_posts
  for each row execute function public.resolve_reports_of_deleted_post();

-- -------------------------------------------------------------------------
-- 4. Conta excluída leva junto os bloqueios e as denúncias que fez
-- -------------------------------------------------------------------------
--
-- Trigger, e não mais uma linha em `delete_own_account()`: assim vale também
-- para a remoção feita pelo admin (`soft_delete_user`), e não é preciso
-- reescrever aquele RPC inteiro. As FKs `on delete cascade` não bastam porque
-- o perfil nunca é apagado de verdade — é soft delete.
--
-- Os bloqueios que OUTRAS pessoas fizeram contra quem saiu também vão: o
-- perfil vira "Removido" e não publica mais nada, então o bloqueio só
-- ocuparia a lista de bloqueados de alguém com um nome que não diz nada.

create or replace function public.cleanup_moderation_of_deleted_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    delete from public.user_blocks
     where blocker_id = new.id or blocked_id = new.id;
    delete from public.content_reports where reporter_id = new.id;
  end if;
  return new;
end;
$$;

create trigger profiles_cleanup_moderation
  after update of deleted_at on public.profiles
  for each row execute function public.cleanup_moderation_of_deleted_profile();

-- -------------------------------------------------------------------------
-- 5. RLS
-- -------------------------------------------------------------------------

alter table public.content_reports enable row level security;
alter table public.user_blocks     enable row level security;

-- Quem denunciou vê a própria denúncia (o app esconde o post denunciado para
-- quem denunciou); o admin vê todas, para moderar.
create policy content_reports_select on public.content_reports
  for select to authenticated
  using (reporter_id = auth.uid() or public.is_admin());

-- `reporter_id = auth.uid()` impede denunciar em nome de outra pessoa.
create policy content_reports_insert on public.content_reports
  for insert to authenticated
  with check (public.is_approved() and reporter_id = auth.uid());

-- Só o admin resolve. Não há policy de DELETE: denúncia não se apaga pela
-- API, fica como registro da moderação.
create policy content_reports_admin_update on public.content_reports
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy user_blocks_select on public.user_blocks
  for select to authenticated using (blocker_id = auth.uid());
create policy user_blocks_insert on public.user_blocks
  for insert to authenticated
  with check (public.is_approved() and blocker_id = auth.uid());
create policy user_blocks_delete on public.user_blocks
  for delete to authenticated using (blocker_id = auth.uid());

-- Sem `updated_at` em user_blocks e sem coluna nova em profiles: nada a
-- acrescentar ao trigger `protect_profile_privileges`.

-- -------------------------------------------------------------------------
-- 6. O feed deixa de trazer os posts de quem a pessoa bloqueou
-- -------------------------------------------------------------------------
--
-- O app também filtra localmente (o bloqueio precisa valer na hora, mesmo
-- offline). O filtro no servidor faz o bloqueio acompanhar a pessoa para
-- outro aparelho e não depender de o cliente lembrar dele.
--
-- Mesmas colunas, na mesma ordem, da migration 0500: `create or replace view`
-- só aceita acrescentar colunas no fim, e `search_prayers` devolve
-- `setof prayer_feed`.

create or replace view public.prayer_feed
with (security_invoker = true) as
select
  p.id,
  p.author_id,
  p.title,
  p.body,
  p.is_anonymous,
  p.answered_at,
  p.answer_note,
  p.created_at,
  p.updated_at,
  case when p.is_anonymous then null else a.full_name  end as author_name,
  case when p.is_anonymous then null else a.avatar_url end as author_avatar_url,
  (select count(*) from public.prayer_interactions i where i.post_id = p.id)
    as praying_count,
  (select count(*) from public.prayer_comments c
     where c.post_id = p.id and c.deleted_at is null) as comment_count,
  exists (select 1 from public.prayer_interactions i
            where i.post_id = p.id and i.user_id = auth.uid()) as is_praying
from public.prayer_posts p
join public.profiles a on a.id = p.author_id
where p.deleted_at is null
  and not exists (select 1 from public.user_blocks b
                   where b.blocker_id = auth.uid()
                     and b.blocked_id = p.author_id);

grant select on public.prayer_feed to authenticated;
