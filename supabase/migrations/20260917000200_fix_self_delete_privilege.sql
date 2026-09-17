-- =========================================================================
-- Correção: excluir a própria conta era impossível para quem não é admin
--
-- `delete_own_account()` (migration 20260807000100) termina zerando
-- `is_approved` no próprio perfil. O trigger `protect_profile_privileges`
-- (migration 20260803000800) recusa qualquer UPDATE em que `role` ou
-- `is_approved` mudem, exceto quando não há `auth.uid()` (acesso direto ao
-- banco), quando quem chama é admin, ou quando a flag de `redeem_invite` está
-- ligada. Nenhuma das três vale numa exclusão de conta feita por um obreiro
-- comum: o RPC é `security definer`, mas `auth.uid()` continua sendo o do
-- usuário, então o trigger via uma pessoa comum rebaixando a si mesma e
-- levantava FORBIDDEN_PRIVILEGE_CHANGE.
--
-- Efeito prático: *Excluir minha conta* falhava para todo obreiro — e é uma
-- exigência da Google Play para apps com cadastro. Só admin conseguia sair.
-- Descoberto ao cobrir o RPC no harness de RLS (local_test §11).
--
-- A saída segue o padrão que já existe para `redeem_invite`: uma flag local à
-- transação, ligada dentro do RPC logo antes do UPDATE. Ela não abre brecha
-- pela API porque só o corpo de uma função `security definer` a liga, e
-- `is_local = true` a apaga no fim da transação.
-- =========================================================================

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

  -- Exceção para delete_own_account(), pelo mesmo mecanismo: a pessoa está
  -- rebaixando a si mesma de propósito, ao sair da base.
  if coalesce(current_setting('app.deleting_own_account', true), 'off') = 'on' then
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
