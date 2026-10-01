-- =========================================================================
-- Apagar de vez o login de quem excluiu a própria conta, 30 dias depois
--
-- -------------------------------------------------------------------------
-- O problema
-- -------------------------------------------------------------------------
--
-- `delete_own_account()` apaga os dados do perfil, mas não o login em
-- `auth.users` — o app não tem a service_role, e o RPC roda com os
-- privilégios de quem chama. A PRIVACIDADE.md prometia que esse login seria
-- "apagado em definitivo" depois de 30 dias, e nada fazia isso: dependia de
-- alguém lembrar de apagar à mão no painel. Enquanto o login existe, o
-- e-mail também não serve para um cadastro novo (o Supabase responde ao
-- signUp de e-mail existente sem enviar nada).
--
-- -------------------------------------------------------------------------
-- A saída
-- -------------------------------------------------------------------------
--
-- Uma função `security definer`, dona `postgres`, apaga o `auth.users` de
-- quem se autoexcluiu há mais de 30 dias, e o `pg_cron` a roda uma vez por
-- dia, dentro do próprio banco. Sem chave nova, sem servidor à parte.
--
-- O `delete` em `auth.users` cascateia para `profiles` e dali para o resto:
-- todas as FKs para `profiles` são `on delete cascade` ou `set null`
-- (conferido na migration). Os pedidos de oração dessa pessoa já tinham sido
-- apagados pelo `delete_own_account`.
--
-- Por que esperar 30 dias, e não apagar na hora: é o prazo que a política de
-- privacidade já publicava, e apagar o login dentro do RPC exigiria dar a ele
-- privilégio sobre o schema `auth` — um RPC chamado pelo app com poder de
-- apagar qualquer login é uma superfície pior do que um job interno.
--
-- -------------------------------------------------------------------------
-- Quem NÃO é apagado
-- -------------------------------------------------------------------------
--
-- Quem foi removido por um admin (`soft_delete_user`). Essa pessoa pode ser
-- restaurada (migration 20260930000400), e apagar o login levaria em cascata
-- os pedidos de oração dela — que ficam no mural por decisão do solicitante.
-- O sinal que separa os dois casos é o mesmo do `restore_member`: só o
-- `delete_own_account` apaga o e-mail do perfil.
-- =========================================================================

create or replace function public.purge_self_deleted_accounts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  -- Recusa quem chega pela API com usuário logado. O revoke abaixo já fecha a
  -- porta, mas grant é fácil de reabrir por engano (um `grant all on all
  -- routines` desfaz) — e esta função apaga logins. O job do pg_cron roda
  -- sem JWT, então `auth.uid()` é nulo para ele.
  if auth.uid() is not null then
    raise exception 'FORBIDDEN_NOT_INTERNAL';
  end if;

  delete from auth.users u
   using public.profiles p
   where p.id = u.id
     and p.deleted_at < now() - interval '30 days'
     and p.email is null;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Ninguém pela API: só o job (e quem tem acesso direto ao banco).
revoke all on function public.purge_self_deleted_accounts()
  from public, anon, authenticated;

comment on function public.purge_self_deleted_accounts() is
  'Apaga o login (auth.users) de quem excluiu a própria conta há mais de 30 '
  'dias. Rodada diariamente pelo pg_cron. Ver PRIVACIDADE.md §6.';

-- -------------------------------------------------------------------------
-- Agendamento
-- -------------------------------------------------------------------------
--
-- Só onde o `pg_cron` existe. No Supabase existe; no Postgres do harness
-- local (`supabase/local_test`) não, e sem este guard a migration quebraria
-- ali — a função continua testável sem o agendamento.
--
-- `cron.schedule` com nome é idempotente: reaplicar a migration atualiza o
-- job em vez de criar um segundo. 06:00 UTC é 03:00 em Joinville, fora do
-- horário de uso.

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule(
      'purge-self-deleted-accounts',
      '0 6 * * *',
      'select public.purge_self_deleted_accounts()'
    );
  else
    raise notice 'pg_cron indisponível: agendamento de purge_self_deleted_accounts ignorado';
  end if;
end;
$$;
