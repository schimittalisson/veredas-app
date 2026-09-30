-- =========================================================================
-- Restaurar um membro removido pelo admin
--
-- -------------------------------------------------------------------------
-- O problema
-- -------------------------------------------------------------------------
--
-- `soft_delete_user` (migration 20260804000100) marca o perfil como removido,
-- mas o login da pessoa em `auth.users` continua existindo — apagá-lo exige a
-- service_role, que nunca entra no app. Consequências:
--
--   - A pessoa não consegue se cadastrar de novo com o mesmo e-mail. O
--     Supabase responde ao signUp como se tivesse dado certo e **não envia
--     e-mail nenhum** (é de propósito: não revelar quais e-mails existem).
--     O app ficava esperando um código que nunca chegava.
--   - Não havia como desfazer uma remoção pelo app: só pelo SQL Editor.
--
-- A saída certa é restaurar a conta que já existe, e não criar outra: a
-- pessoa volta com o mesmo login, e o histórico dela (escalas, pedidos de
-- oração) continua ligado a ela. O app passou a mandar quem tenta se cadastrar
-- ou entrar nessa situação pedir a restauração a um admin.
--
-- -------------------------------------------------------------------------
-- Quem NÃO pode ser restaurado
-- -------------------------------------------------------------------------
--
-- Quem excluiu a própria conta (`delete_own_account`). Ali os dados já foram
-- apagados — nome virou "Removido", e-mail, telefone e foto foram limpos — e
-- a saída foi decisão da pessoa, não de um admin. "Restaurar" traria de volta
-- um perfil vazio chamado "Removido". O sinal é `email is null`: todo perfil
-- nasce com o e-mail do cadastro (`handle_new_user`) e só o
-- `delete_own_account` o apaga.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Lista dos removidos (só admin)
-- -------------------------------------------------------------------------
--
-- RPC e não um SELECT direto do app: o admin até lê perfis removidos pela
-- policy `profiles_admin_all`, mas a regra "quem excluiu a própria conta não
-- entra" ficaria espalhada no cliente. E os removidos não chegam ao cache do
-- app — o sync descarta lápides — então a tela consulta o servidor na hora.

create or replace function public.list_removed_members()
returns table (
  id         uuid,
  full_name  text,
  email      text,
  deleted_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN_NOT_ADMIN';
  end if;

  return query
    select p.id, p.full_name, p.email, p.deleted_at
      from public.profiles p
     where p.deleted_at is not null
       and p.email is not null
     order by p.deleted_at desc;
end;
$$;

revoke all on function public.list_removed_members() from public, anon;
grant execute on function public.list_removed_members() to authenticated;

-- -------------------------------------------------------------------------
-- 2. Restaurar (só admin)
-- -------------------------------------------------------------------------
--
-- A pessoa volta **aprovada e como obreiro**, mesmo que fosse admin antes:
-- devolver privilégio de administração deve ser uma decisão explícita, feita
-- na tela de Membros, e não efeito colateral de desfazer uma remoção.
--
-- O UPDATE passa pelo `protect_profile_privileges` porque quem chama é admin.

create or replace function public.restore_member(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN_NOT_ADMIN';
  end if;

  select * into v_profile from public.profiles where id = p_user_id;
  if v_profile.id is null or v_profile.deleted_at is null then
    raise exception 'USER_NOT_FOUND';
  end if;
  if v_profile.email is null then
    raise exception 'USER_SELF_DELETED';
  end if;

  update public.profiles
     set deleted_at  = null,
         is_approved = true,
         role        = 'obreiro',
         updated_at  = now()
   where id = p_user_id;
end;
$$;

revoke all on function public.restore_member(uuid) from public, anon;
grant execute on function public.restore_member(uuid) to authenticated;
