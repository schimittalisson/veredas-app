-- =========================================================================
-- §9 — RPCs de administração
--
-- Estas funções permitem que um admin gerencie membros, convites e
-- responsáveis por escala através da API do app. Todas são `security
-- definer` com `search_path = public` porque:
--
-- 1. O chamador é `authenticated`, mas as policies de profiles/invites
--    já permitem `is_admin()` — então as RPCs poderiam rodar como
--    `security invoker`. O `security definer` é por consistência com
--    `redeem_invite` e para evitar reavaliação de RLS em cada sub-consulta.
--
-- 2. `set_role` e `set_approval` contornam o trigger
--    `protect_profile_privileges` (0800) via `set_config('app.admin_action',
--    'on', true)` — mesma técnica que `redeem_invite` usa com
--    `app.redeeming_invite`. A flag é `is_local = true` e expira no fim da
--    transação.
--
-- 3. A proteção contra auto-rebaixamento (não rebaixar a si mesmo se for o
--    único admin) é validada AQUI, no banco, não só na UI. A UI pode ser
--    burlada; o banco não.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 9.1 set_approval — aprovar ou revogar acesso de um obreiro.
-- -------------------------------------------------------------------------
create or replace function public.set_approval(
  p_user_id uuid,
  p_approved boolean
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

  -- Libera o trigger protect_profile_privileges.
  perform set_config('app.admin_action', 'on', true);

  update public.profiles
     set is_approved = p_approved,
         updated_at = now()
   where id = p_user_id and deleted_at is null;

  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;
end;
$$;

revoke all on function public.set_approval(uuid, boolean) from public, anon;
grant execute on function public.set_approval(uuid, boolean) to authenticated;

-- -------------------------------------------------------------------------
-- 9.2 set_role — promover a admin ou rebaixar a obreiro.
--
-- Proteção: impede que o admin rebaixe a si mesmo se for o ÚNICO admin
-- ativo. Sem isto, a base ficaria sem nenhum admin e trancaria.
-- -------------------------------------------------------------------------
create or replace function public.set_role(
  p_user_id uuid,
  p_role public.app_role
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active_admins integer;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN_NOT_ADMIN';
  end if;

  -- Proteção de auto-rebaixamento: se o alvo é o próprio chamador e o novo
  -- papel não é admin, verifica se há pelo menos 2 admins ativos.
  if p_user_id = auth.uid() and p_role <> 'admin' then
    select count(*) into v_active_admins
      from public.profiles
     where role = 'admin' and is_approved and deleted_at is null;

    if v_active_admins <= 1 then
      raise exception 'CANNOT_DEMOTE_LAST_ADMIN';
    end if;
  end if;

  perform set_config('app.admin_action', 'on', true);

  update public.profiles
     set role = p_role,
         updated_at = now()
   where id = p_user_id and deleted_at is null;

  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;
end;
$$;

revoke all on function public.set_role(uuid, public.app_role) from public, anon;
grant execute on function public.set_role(uuid, public.app_role) to authenticated;

-- -------------------------------------------------------------------------
-- 9.3 soft_delete_user — marca o perfil como removido (deleted_at = now()).
--
-- Não chama auth.admin.delete_user (isso exigiria service_role, que nunca
-- entra no app). O perfil fica com deleted_at setado; a exclusão física do
-- auth.users é feita manualmente pelo admin via SQL Editor ou Edge Function
-- (LGPD — ver PRIVACIDADE.md §6).
--
-- Mesma proteção de auto-exclusão que set_role: não pode remover a si mesmo
-- se for o único admin.
-- -------------------------------------------------------------------------
create or replace function public.soft_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active_admins integer;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN_NOT_ADMIN';
  end if;

  if p_user_id = auth.uid() then
    select count(*) into v_active_admins
      from public.profiles
     where role = 'admin' and is_approved and deleted_at is null;

    if v_active_admins <= 1 then
      raise exception 'CANNOT_DELETE_LAST_ADMIN';
    end if;
  end if;

  update public.profiles
     set deleted_at = now(),
         is_approved = false,
         updated_at = now()
   where id = p_user_id and deleted_at is null;

  if not found then
    raise exception 'USER_NOT_FOUND';
  end if;
end;
$$;

revoke all on function public.soft_delete_user(uuid) from public, anon;
grant execute on function public.soft_delete_user(uuid) to authenticated;

-- -------------------------------------------------------------------------
-- 9.4 create_invite — gera um novo convite.
--
-- O código é gerado automaticamente se não fornecido (6 chars alfanuméricos
-- maiúsculos, sem 0/O/1/I para evitar confusão ao ditar por telefone), mas
-- o admin pode passar um código customizado.
-- -------------------------------------------------------------------------
create or replace function public.create_invite(
  p_role public.app_role default 'obreiro',
  p_max_uses integer default 1,
  p_expires_at timestamptz default null,
  p_note text default null,
  p_code text default null
)
returns public.invites
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_invite public.invites;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN_NOT_ADMIN';
  end if;

  if p_max_uses <= 0 then
    raise exception 'INVALID_MAX_USES';
  end if;

  -- Se o código não foi fornecido, gera um aleatório sem 0/O/1/I.
  -- string_agg é agregação (não janela), então vai num subselect com
  -- generate_series como fonte de linhas.
  v_code := coalesce(
    upper(trim(p_code)),
    (
      select string_agg(
               substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                      1 + floor(random() * 31)::int, 1),
               ''
             )
        from generate_series(1, 6)
    )
  );

  insert into public.invites (code, role, note, max_uses, expires_at, created_by)
  values (v_code, p_role, p_note, p_max_uses, p_expires_at, auth.uid())
  returning * into v_invite;

  return v_invite;
end;
$$;

revoke all on function public.create_invite(public.app_role, integer, timestamptz, text, text) from public, anon;
grant execute on function public.create_invite(public.app_role, integer, timestamptz, text, text) to authenticated;

-- -------------------------------------------------------------------------
-- 9.5 revoke_invite — revoga um convite (set revoked_at = now()).
-- -------------------------------------------------------------------------
create or replace function public.revoke_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN_NOT_ADMIN';
  end if;

  update public.invites
     set revoked_at = now(),
         updated_at = now()
   where id = p_invite_id and deleted_at is null;

  if not found then
    raise exception 'INVITE_NOT_FOUND';
  end if;
end;
$$;

revoke all on function public.revoke_invite(uuid) from public, anon;
grant execute on function public.revoke_invite(uuid) to authenticated;

-- -------------------------------------------------------------------------
-- 9.6 add_scale_manager — designa um obreiro como responsável por um tipo
-- de escala.
-- -------------------------------------------------------------------------
create or replace function public.add_scale_manager(
  p_scale_type_id uuid,
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

  -- Verifica que o usuário alvo é um obreiro aprovado.
  if not exists (
    select 1 from public.profiles
     where id = p_user_id and is_approved and deleted_at is null
  ) then
    raise exception 'USER_NOT_APPROVED';
  end if;

  insert into public.scale_managers (scale_type_id, user_id)
  values (p_scale_type_id, p_user_id)
  on conflict (scale_type_id, user_id) do nothing;
end;
$$;

revoke all on function public.add_scale_manager(uuid, uuid) from public, anon;
grant execute on function public.add_scale_manager(uuid, uuid) to authenticated;

-- -------------------------------------------------------------------------
-- 9.7 remove_scale_manager — remove um responsável de um tipo de escala.
-- -------------------------------------------------------------------------
create or replace function public.remove_scale_manager(
  p_scale_type_id uuid,
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

  delete from public.scale_managers
   where scale_type_id = p_scale_type_id
     and user_id = p_user_id;

  if not found then
    raise exception 'SCALE_MANAGER_NOT_FOUND';
  end if;
end;
$$;

revoke all on function public.remove_scale_manager(uuid, uuid) from public, anon;
grant execute on function public.remove_scale_manager(uuid, uuid) to authenticated;

-- -------------------------------------------------------------------------
-- Atualiza o trigger protect_profile_privileges para reconhecer a flag
-- app.admin_action (mesma técnica de app.redeeming_invite).
-- -------------------------------------------------------------------------
create or replace function public.protect_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Exceção para a RPC redeem_invite, que precisa promover o próprio usuário.
  -- A flag é setada com is_local = true e morre no fim da transação, então a
  -- brecha não vaza para outros updates da mesma conexão.
  if coalesce(current_setting('app.redeeming_invite', true), 'off') = 'on' then
    return new;
  end if;

  -- Exceção para as RPCs de admin (set_role, set_approval), que precisam
  -- alterar role/is_approved de outros usuários.
  if coalesce(current_setting('app.admin_action', true), 'off') = 'on' then
    return new;
  end if;

  -- Sem auth.uid() não existe usuário final na requisição: é acesso direto ao
  -- banco (SQL Editor, psql, migration) ou uma chamada com service_role.
  --
  -- Esta exceção é OBRIGATÓRIA para bootstrapar a base. O primeiro admin é
  -- promovido por um UPDATE manual no SQL Editor (supabase/README.md passo 7),
  -- onde auth.uid() é NULL — sem esta cláusula o trigger derruba esse UPDATE
  -- com FORBIDDEN_PRIVILEGE_CHANGE e NÃO EXISTE forma de criar o primeiro
  -- admin. Verificado num Postgres 17 local antes de aplicar.
  --
  -- Não abre brecha pela API: as policies de profiles são `to authenticated` e
  -- exigem `id = auth.uid()`, então uma requisição anônima não alcança linha
  -- alguma para atualizar. Quem tem acesso direto ao banco ou a service_role
  -- já é privilegiado por definição.
  if auth.uid() is null then
    return new;
  end if;

  if public.is_admin() then
    return new;
  end if;

  if new.role is distinct from old.role
     or new.is_approved is distinct from old.is_approved then
    raise exception 'FORBIDDEN_PRIVILEGE_CHANGE';
  end if;

  return new;
end;
$$;
