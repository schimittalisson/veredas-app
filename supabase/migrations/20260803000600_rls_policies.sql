-- =========================================================================
-- §6 — Row Level Security
--
-- No Supabase, uma tabela SEM RLS é totalmente pública para a anon key — que
-- está embarcada no APK. RLS habilitado em toda tabela não é opcional.
--
-- Ocultar um botão na UI não é controle de acesso. Toda permissão da tela tem
-- uma policy correspondente aqui.
-- =========================================================================

alter table public.profiles            enable row level security;
alter table public.invites             enable row level security;
alter table public.scale_types         enable row level security;
alter table public.scale_managers      enable row level security;
alter table public.scale_assignments   enable row level security;
alter table public.events              enable row level security;
alter table public.weekly_slots        enable row level security;
alter table public.prayer_posts        enable row level security;
alter table public.prayer_interactions enable row level security;
alter table public.prayer_comments     enable row level security;
alter table public.announcements       enable row level security;
alter table public.base_info           enable row level security;
alter table public.social_links        enable row level security;

-- -------------------------------------------------------------------------
-- 6.1 profiles
-- -------------------------------------------------------------------------

-- Todo usuário autenticado vê o próprio perfil. Isto é necessário para ele
-- descobrir que ainda não foi aprovado — sem esta policy ele não veria nada e
-- a tela /aguardando não teria como saber o que exibir.
create policy profiles_select_self on public.profiles
  for select to authenticated
  using (id = auth.uid());

-- Aprovados veem a lista de obreiros (para escolher responsáveis de escala e
-- ver autores de post).
create policy profiles_select_approved on public.profiles
  for select to authenticated
  using (public.is_approved() and deleted_at is null);

-- Edita o próprio perfil, MAS não pode mexer em role/is_approved.
-- Uma policy não consegue comparar new vs old, então a proibição real está no
-- trigger protect_profile_privileges (0800). Defesa em profundidade.
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy profiles_admin_all on public.profiles
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- -------------------------------------------------------------------------
-- 6.2 invites
-- -------------------------------------------------------------------------

-- Só admin lê/gera convites. Quem se cadastra NÃO consulta a tabela: valida
-- via RPC redeem_invite (security definer), que ignora RLS. Assim um convite
-- válido não pode ser descoberto por enumeração.
create policy invites_admin_all on public.invites
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- -------------------------------------------------------------------------
-- 6.3 Escalas — o requisito central de permissão do app
-- -------------------------------------------------------------------------

create policy scale_types_select on public.scale_types
  for select to authenticated
  using (public.is_approved() and deleted_at is null);

create policy scale_types_admin_write on public.scale_types
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy scale_managers_select on public.scale_managers
  for select to authenticated
  using (public.is_approved());

create policy scale_managers_admin_write on public.scale_managers
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Todo obreiro aprovado LÊ todas as escalas.
create policy scale_assignments_select on public.scale_assignments
  for select to authenticated
  using (public.is_approved() and deleted_at is null);

-- ...mas só escreve na escala que gerencia. Esta é a policy que implementa
-- "o responsável pelo Servir ao Todo é a única pessoa que pode editá-la".
create policy scale_assignments_insert on public.scale_assignments
  for insert to authenticated
  with check (public.manages_scale(scale_type_id));

-- using      -> pode alterar linhas da escala que gerencia hoje.
-- with check -> não pode "mover" a linha para uma escala que não gerencia.
-- Os dois são necessários: só o using permitiria roubar uma linha para outro
-- tipo de escala; só o with check permitiria editar linha alheia.
create policy scale_assignments_update on public.scale_assignments
  for update to authenticated
  using (public.manages_scale(scale_type_id))
  with check (public.manages_scale(scale_type_id));

-- Delete físico existe apenas para admin (limpeza). O app usa soft delete
-- (update de deleted_at), coberto pela policy de update acima.
create policy scale_assignments_delete on public.scale_assignments
  for delete to authenticated
  using (public.is_admin());

-- -------------------------------------------------------------------------
-- 6.4 Agenda
-- -------------------------------------------------------------------------
create policy events_select on public.events
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy events_admin_write on public.events
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy weekly_slots_select on public.weekly_slots
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy weekly_slots_admin_write on public.weekly_slots
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- -------------------------------------------------------------------------
-- 6.5 Mural de oração
-- -------------------------------------------------------------------------
create policy prayer_posts_select on public.prayer_posts
  for select to authenticated using (public.is_approved() and deleted_at is null);

-- author_id = auth.uid() impede publicar em nome de outra pessoa.
create policy prayer_posts_insert on public.prayer_posts
  for insert to authenticated
  with check (public.is_approved() and author_id = auth.uid());

-- Autor edita o próprio; admin modera qualquer um.
create policy prayer_posts_update on public.prayer_posts
  for update to authenticated
  using (author_id = auth.uid() or public.is_admin())
  with check (author_id = auth.uid() or public.is_admin());

create policy prayer_posts_delete on public.prayer_posts
  for delete to authenticated
  using (author_id = auth.uid() or public.is_admin());

create policy prayer_interactions_select on public.prayer_interactions
  for select to authenticated using (public.is_approved());
create policy prayer_interactions_insert on public.prayer_interactions
  for insert to authenticated
  with check (public.is_approved() and user_id = auth.uid());
create policy prayer_interactions_delete on public.prayer_interactions
  for delete to authenticated using (user_id = auth.uid());

create policy prayer_comments_select on public.prayer_comments
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy prayer_comments_insert on public.prayer_comments
  for insert to authenticated
  with check (public.is_approved() and author_id = auth.uid());
create policy prayer_comments_update on public.prayer_comments
  for update to authenticated
  using (author_id = auth.uid() or public.is_admin())
  with check (author_id = auth.uid() or public.is_admin());
create policy prayer_comments_delete on public.prayer_comments
  for delete to authenticated using (author_id = auth.uid() or public.is_admin());

-- -------------------------------------------------------------------------
-- 6.6 Início / institucional
-- -------------------------------------------------------------------------
create policy announcements_select on public.announcements
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy announcements_admin_write on public.announcements
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy base_info_select on public.base_info
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy base_info_admin_write on public.base_info
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy social_links_select on public.social_links
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy social_links_admin_write on public.social_links
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
