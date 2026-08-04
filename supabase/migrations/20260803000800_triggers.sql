-- =========================================================================
-- §8 — Triggers
-- =========================================================================

-- -------------------------------------------------------------------------
-- updated_at automático.
--
-- Sem isto o sync incremental NÃO funciona: o cliente offline não teria como
-- saber que a linha mudou, porque o pull filtra por `updated_at > marca d'água`.
-- Confiar no app para mandar updated_at seria confiar no relógio do celular.
-- -------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'profiles','invites','scale_types','scale_managers','scale_assignments',
    'events','weekly_slots','prayer_posts','prayer_interactions',
    'prayer_comments','announcements','base_info','social_links'
  ] loop
    execute format(
      'create trigger %I_touch_updated_at before update on public.%I
         for each row execute function public.touch_updated_at()', t, t);
  end loop;
end;
$$;

-- -------------------------------------------------------------------------
-- Impede escalada de privilégio: um usuário comum não pode alterar o próprio
-- role nem is_approved, mesmo tendo permissão de update no perfil.
--
-- A policy profiles_update_self (0600) não consegue fazer isto sozinha, porque
-- uma policy não vê o valor ANTIGO da linha. Só um trigger compara old vs new.
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

create trigger profiles_protect_privileges
  before update on public.profiles
  for each row execute function public.protect_profile_privileges();
