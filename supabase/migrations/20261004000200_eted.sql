-- =========================================================================
-- ETED: alunos da escola e o cronograma próprio dela
--
-- A ETED roda na base todo ano. Os alunos moram lá por cinco meses ou mais,
-- não são obreiros, e precisam do app para quase tudo: Início, Agenda,
-- Escalas (sobretudo a lavanderia) e Arquivos. Ficam de fora só do mural de
-- oração. A escola também tem um cronograma semanal próprio, que aparece ao
-- lado do cronograma da base e é mantido pelos líderes da ETED.
--
-- -------------------------------------------------------------------------
-- O aluno é um papel, e não uma flag
-- -------------------------------------------------------------------------
--
-- `role = 'aluno'` (migration anterior) reaproveita o caminho inteiro do
-- convite: `invites.role` já existe, o `redeem_invite` já copia o papel do
-- convite para o perfil, e o `set_role` do admin já troca papel. No fim da
-- escola, o aluno que fica na base vira obreiro pela tela de Membros; os
-- outros são removidos. Nada disso precisou de RPC nova.
--
-- -------------------------------------------------------------------------
-- O que muda de permissão
-- -------------------------------------------------------------------------
--
-- Toda policy de leitura do schema usa `is_approved()`. Para o aluno,
-- aprovado, isso já libera o que ele deve ver — e também o mural. Esconder a
-- aba no app não é controle de acesso (a anon key está no APK), então o mural
-- passa a exigir `is_member()`: aprovado E não aluno.
--
-- Só o mural muda. O resto continua em `is_approved()` de propósito: o aluno
-- lê eventos, cronogramas, escalas, avisos e arquivos, reserva a lavanderia,
-- e é escalado como qualquer um. Ele também lê `profiles` (nome, e-mail e
-- telefone dos obreiros), porque o nome de quem está escalado vem dali.
--
-- Um app antigo não conhece o papel e o trata como obreiro
-- (`AppRole.fromWire`), mostrando a aba do mural. Ela fica vazia, e publicar
-- falha no RLS. Os alunos chegam pelo app novo, então isto só acontece com
-- quem não atualizou.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. is_member — aprovado e não aluno
-- -------------------------------------------------------------------------
-- security definer pelo mesmo motivo de `is_approved()`: consulta `profiles`
-- de dentro de policies, e sem isso a policy de `profiles` recursaria.
create or replace function public.is_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.is_approved and p.role <> 'aluno' from public.profiles p
      where p.id = auth.uid() and p.deleted_at is null),
    false
  );
$$;

revoke all on function public.is_member() from public;
grant execute on function public.is_member() to authenticated;

-- -------------------------------------------------------------------------
-- 2. Mural de oração: só membros
-- -------------------------------------------------------------------------
-- Leitura: a view `prayer_feed` (que é como o mural é servido) e as tabelas
-- auxiliares. Escrita: publicar, orar, comentar, denunciar e bloquear. O
-- bloqueio também entra porque ele só existe para filtrar o mural.
--
-- As policies de UPDATE/DELETE por autoria (`author_id = auth.uid()`) não
-- mudam: um aluno não tem post, e quem era obreiro e virou aluno continua
-- podendo apagar o que escreveu.

drop policy if exists prayer_posts_select on public.prayer_posts;
create policy prayer_posts_select on public.prayer_posts
  for select to authenticated
  using (public.is_member()
         and (author_id = auth.uid() or public.is_admin()));

drop policy if exists prayer_posts_insert on public.prayer_posts;
create policy prayer_posts_insert on public.prayer_posts
  for insert to authenticated
  with check (public.is_member() and author_id = auth.uid());

drop policy if exists prayer_interactions_select on public.prayer_interactions;
create policy prayer_interactions_select on public.prayer_interactions
  for select to authenticated using (public.is_member());

drop policy if exists prayer_interactions_insert on public.prayer_interactions;
create policy prayer_interactions_insert on public.prayer_interactions
  for insert to authenticated
  with check (public.is_member() and user_id = auth.uid());

drop policy if exists prayer_comments_select on public.prayer_comments;
create policy prayer_comments_select on public.prayer_comments
  for select to authenticated
  using (public.is_member() and deleted_at is null);

drop policy if exists prayer_comments_insert on public.prayer_comments;
create policy prayer_comments_insert on public.prayer_comments
  for insert to authenticated
  with check (public.is_member() and author_id = auth.uid());

drop policy if exists content_reports_insert on public.content_reports;
create policy content_reports_insert on public.content_reports
  for insert to authenticated
  with check (public.is_member() and reporter_id = auth.uid());

drop policy if exists user_blocks_insert on public.user_blocks;
create policy user_blocks_insert on public.user_blocks
  for insert to authenticated
  with check (public.is_member() and blocker_id = auth.uid());

-- A view roda com os privilégios do dono (migration 20260930000200) e refaz
-- os filtros do RLS à mão. Por isso o portão é trocado AQUI também — trocar
-- só a policy da tabela não fecharia nada, porque a view não passa por ela.
-- Corpo idêntico ao da 20260930000200, exceto `is_member()` no lugar de
-- `is_approved()`. `create or replace` mantém as opções e os grants.
create or replace view public.prayer_feed as
select
  p.id,
  case when p.is_anonymous and p.author_id is distinct from auth.uid()
       then '00000000-0000-0000-0000-000000000000'::uuid
       else p.author_id
  end as author_id,
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
where public.is_member()
  and p.deleted_at is null
  and not exists (select 1 from public.user_blocks b
                   where b.blocker_id = auth.uid()
                     and b.blocked_id = p.author_id);

-- -------------------------------------------------------------------------
-- 3. Qual cronograma: coluna em `weekly_slots`, e não tabela nova
-- -------------------------------------------------------------------------
-- O cronograma da ETED é uma grade semanal igual à da base. Uma coluna
-- reaproveita a tabela, o sync, o editor e a grade do app inteiros.
--
-- O preço: um app antigo não conhece a coluna e mostra os horários da ETED
-- misturados aos da base. Some quando a pessoa atualiza. Uma tabela separada
-- evitaria isso, mas duplicaria o motor de sync e a tela por uma janela de
-- transição.
--
-- `text` com CHECK, e não enum, pelo mesmo motivo de `scale_types.cadence`:
-- acrescentar um valor a um enum não pode ser feito na mesma transação que o
-- usa, e um CHECK se troca numa migration comum.
alter table public.weekly_slots
  add column if not exists schedule text not null default 'base';

alter table public.weekly_slots
  drop constraint if exists weekly_slots_schedule_check;
alter table public.weekly_slots
  add constraint weekly_slots_schedule_check
  check (schedule in ('base', 'eted'));

-- -------------------------------------------------------------------------
-- 4. Líderes de cronograma
-- -------------------------------------------------------------------------
-- Mesmo desenho de `scale_managers`: uma linha por (cronograma, pessoa),
-- nomeada pelo admin. Os líderes da ETED editam o cronograma da ETED e nada
-- mais. O admin edita todos sem precisar de linha aqui.
--
-- O CHECK aceita 'base' para a tabela não precisar mudar se a base um dia
-- quiser delegar o cronograma dela; hoje o app só oferece a ETED.
create table if not exists public.schedule_managers (
  schedule    text not null check (schedule in ('base', 'eted')),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (schedule, user_id)
);

create index if not exists schedule_managers_user_idx
  on public.schedule_managers (user_id);

alter table public.schedule_managers enable row level security;

-- Todo aprovado lê: o app de cada um precisa saber se mostra o botão de
-- criar na aba da ETED, e o admin precisa listar os líderes.
create policy schedule_managers_select on public.schedule_managers
  for select to authenticated using (public.is_approved());

create policy schedule_managers_admin_write on public.schedule_managers
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Edita este cronograma? Admin edita todos. Exige aprovação também do líder:
-- revogar o acesso de alguém tem de tirar a edição junto, sem depender de o
-- admin lembrar de removê-lo da lista de líderes.
create or replace function public.manages_schedule(p_schedule text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or (
    public.is_approved() and exists (
      select 1 from public.schedule_managers m
       where m.schedule = p_schedule
         and m.user_id = auth.uid()
    )
  );
$$;

revoke all on function public.manages_schedule(text) from public;
grant execute on function public.manages_schedule(text) to authenticated;

-- -------------------------------------------------------------------------
-- 5. Escrita em `weekly_slots` por cronograma
-- -------------------------------------------------------------------------
-- O USING olha a linha antiga e o WITH CHECK a nova: um líder da ETED não
-- consegue mover um horário da ETED para a base, nem editar um da base.
--
-- `for all` inclui SELECT, então o líder enxerga as lápides do cronograma
-- dele. O pull descarta lápides (ver `SyncService._doPull`), e o mesmo já
-- acontecia com o admin.
drop policy if exists weekly_slots_admin_write on public.weekly_slots;
create policy weekly_slots_write on public.weekly_slots
  for all to authenticated
  using (public.manages_schedule(schedule))
  with check (public.manages_schedule(schedule));

-- -------------------------------------------------------------------------
-- 6. RPCs de admin para nomear e remover líderes
-- -------------------------------------------------------------------------
-- Espelham `add_scale_manager`/`remove_scale_manager`, com os mesmos códigos
-- de erro: o app já sabe traduzir cada um.
create or replace function public.add_schedule_manager(
  p_schedule text,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN_NOT_ADMIN';
  end if;

  if not exists (
    select 1 from public.profiles
     where id = p_user_id and is_approved and deleted_at is null
  ) then
    raise exception 'USER_NOT_APPROVED';
  end if;

  insert into public.schedule_managers (schedule, user_id, assigned_by)
  values (p_schedule, p_user_id, auth.uid())
  on conflict (schedule, user_id) do nothing;
end;
$$;

revoke all on function public.add_schedule_manager(text, uuid) from public, anon;
grant execute on function public.add_schedule_manager(text, uuid) to authenticated;

create or replace function public.remove_schedule_manager(
  p_schedule text,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN_NOT_ADMIN';
  end if;

  delete from public.schedule_managers
   where schedule = p_schedule
     and user_id = p_user_id;

  if not found then
    raise exception 'SCALE_MANAGER_NOT_FOUND';
  end if;
end;
$$;

revoke all on function public.remove_schedule_manager(text, uuid) from public, anon;
grant execute on function public.remove_schedule_manager(text, uuid) to authenticated;
