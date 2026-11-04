-- =========================================================================
-- Notificação push de aviso novo
--
-- Peças:
--
-- 1. `push_devices`: o FID (Firebase Installation ID) de cada aparelho, e de
--    quem ele é. O app registra ao entrar e remove ao sair, pelas RPCs abaixo.
--    É FID, e não o antigo "registration token": o `firebase_messaging` 17
--    depreciou os tokens, e o FCM HTTP v1 envia para `message.fid`.
-- 2. Trigger em `announcements`: a cada aviso inserido, chama a Edge Function
--    `notify-announcement` (via `pg_net`), que lê os aparelhos com a
--    service_role e envia pelo FCM. O passo a passo de configuração está em
--    `supabase/README.md` §8.
--
-- -------------------------------------------------------------------------
-- Por que RPC, e não escrita direta na tabela
-- -------------------------------------------------------------------------
--
-- Um FID pertence ao aparelho, não à pessoa. Quando outra pessoa entra no
-- mesmo celular, o FID é o mesmo e precisa mudar de dono. Com RLS
-- (`user_id = auth.uid()`), o upsert dessa linha é recusado — ela é de outro
-- usuário. A RPC `security definer` faz a troca, e só para quem está logado.
--
-- -------------------------------------------------------------------------
-- O trigger nunca derruba o aviso
-- -------------------------------------------------------------------------
--
-- Push é acessório: se a URL da função ou o segredo não estiverem no Vault,
-- se o `pg_net` não existir (o Postgres do harness não tem), ou se qualquer
-- coisa falhar, o aviso é gravado do mesmo jeito. Por isso o bloco de
-- `exception when others`. O `pg_net` é assíncrono: a chamada HTTP sai depois
-- do commit, e a escrita do aviso não espera o FCM.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Tokens
-- -------------------------------------------------------------------------

create table if not exists public.push_devices (
  fid        text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  platform   text not null check (platform in ('android', 'ios')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_devices_user_idx on public.push_devices (user_id);

alter table public.push_devices enable row level security;

-- Só leitura dos próprios aparelhos; a escrita passa pelas RPCs. A Edge Function
-- usa a service_role, que ignora o RLS.
drop policy if exists push_devices_select_own on public.push_devices;
create policy push_devices_select_own on public.push_devices
  for select to authenticated using (user_id = auth.uid());

-- Regra da migration 20261021000100: tabela nova concede no mesmo arquivo.
grant select, insert, update, delete on public.push_devices
  to authenticated, service_role;

create or replace function public.register_push_device(
  p_fid text, p_platform text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'FORBIDDEN_NOT_AUTHENTICATED';
  end if;
  if p_fid is null or length(p_fid) < 10 then
    raise exception 'INVALID_PUSH_DEVICE';
  end if;

  insert into public.push_devices (fid, user_id, platform)
  values (p_fid, auth.uid(), p_platform)
  on conflict (fid) do update
     set user_id    = excluded.user_id,
         platform   = excluded.platform,
         updated_at = now();
end;
$$;

create or replace function public.unregister_push_device(p_fid text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.push_devices
   where fid = p_fid and user_id = auth.uid();
$$;

revoke all on function public.register_push_device(text, text) from public, anon;
revoke all on function public.unregister_push_device(text) from public, anon;
grant execute on function public.register_push_device(text, text) to authenticated;
grant execute on function public.unregister_push_device(text) to authenticated;

-- Conta removida ou excluída: os aparelhos dela param de receber. O perfil é
-- soft delete, então o `on delete cascade` da FK não dispara.
create or replace function public.cleanup_push_devices_of_deleted_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    delete from public.push_devices where user_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_cleanup_push_devices on public.profiles;
create trigger profiles_cleanup_push_devices
  after update of deleted_at on public.profiles
  for each row execute function public.cleanup_push_devices_of_deleted_profile();

-- -------------------------------------------------------------------------
-- 2. Aviso novo → Edge Function
-- -------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
end
$$;

-- A URL da função e o segredo compartilhado moram no Vault, não aqui: a
-- migration vai para o git, e o segredo é o que impede qualquer pessoa de
-- chamar a função e disparar push para a base inteira.
create or replace function public.notify_new_announcement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url    text;
  v_secret text;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  begin
    select decrypted_secret into v_url
      from vault.decrypted_secrets where name = 'push_function_url';
    select decrypted_secret into v_secret
      from vault.decrypted_secrets where name = 'push_webhook_secret';
    if v_url is null or v_secret is null then
      return new;
    end if;

    perform net.http_post(
      url     := v_url,
      body    := jsonb_build_object('type', 'announcement', 'id', new.id),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_secret
      )
    );
  exception when others then
    -- Ver o cabeçalho: push nunca derruba o aviso.
    raise warning 'notify_new_announcement: %', sqlerrm;
  end;

  return new;
end;
$$;

drop trigger if exists announcements_notify on public.announcements;
create trigger announcements_notify
  after insert on public.announcements
  for each row execute function public.notify_new_announcement();
