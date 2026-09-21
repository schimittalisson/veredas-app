-- =========================================================================
-- Convite sem limite de usos e edição do convite pelo app
--
-- A base passou de ~20 para ~30 obreiros e o convite inicial (VEREDAS2026)
-- nasceu com `max_uses = 20`: o 21º obreiro bateria em INVITE_EXHAUSTED sem
-- que ninguém tivesse como aumentar o número — não existia RPC de edição, e
-- criar outro convite com o MESMO código esbarra no índice único.
--
-- Duas mudanças:
--   1. `max_uses` aceita null, que passa a significar "sem limite".
--   2. `update_invite` permite ao admin trocar código, papel, limite,
--      validade e observação de um convite que já existe.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. max_uses nullable = ilimitado
--
-- O CHECK original (`max_uses > 0`) continua valendo e não precisa mudar: em
-- SQL um CHECK só reprova quando a expressão é FALSE, e `null > 0` é NULL.
-- -------------------------------------------------------------------------
alter table public.invites alter column max_uses drop not null;

comment on column public.invites.max_uses is
  'Número máximo de resgates. NULL = sem limite.';

-- O convite inicial da base. O guard `= 20` é para não desfazer um limite que
-- o admin tenha ajustado de propósito depois; num banco novo esta linha ainda
-- não existe (o seed roda depois das migrations) e o UPDATE é no-op — lá o
-- próprio seed já insere com null.
update public.invites
   set max_uses = null, updated_at = now()
 where upper(code) = 'VEREDAS2026'
   and max_uses = 20;

-- -------------------------------------------------------------------------
-- 2. redeem_invite — só checa esgotamento quando há limite.
--
-- Recriada por inteiro (e não por patch) porque `create or replace` substitui
-- o corpo todo; o restante é idêntico à versão da migration 0500.
-- -------------------------------------------------------------------------
create or replace function public.redeem_invite(invite_code text)
returns public.app_role
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.invites;
  v_uid    uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- for update: serializa resgates concorrentes, para max_uses não ser furado
  -- por duas pessoas resgatando o último uso no mesmo instante.
  select * into v_invite
    from public.invites
   where upper(code) = upper(trim(invite_code))
     and deleted_at is null
   for update;

  if not found                       then raise exception 'INVITE_NOT_FOUND'; end if;
  if v_invite.revoked_at is not null  then raise exception 'INVITE_REVOKED';   end if;
  if v_invite.expires_at is not null
     and v_invite.expires_at < now()  then raise exception 'INVITE_EXPIRED';    end if;
  -- max_uses null = ilimitado: não há como esgotar.
  if v_invite.max_uses is not null
     and v_invite.uses >= v_invite.max_uses then raise exception 'INVITE_EXHAUSTED'; end if;

  -- Idempotente: se já aprovado, não consome outro uso. Protege o caso do app
  -- reenviar o resgate (ex.: retry de rede) sem gastar vaga do convite.
  if exists (select 1 from public.profiles
              where id = v_uid and is_approved) then
    return (select role from public.profiles where id = v_uid);
  end if;

  -- Libera o trigger protect_profile_privileges (0800) para esta transação.
  -- set_config com is_local = true expira no fim da transação, então a
  -- permissão não vaza para outras operações da mesma conexão.
  perform set_config('app.redeeming_invite', 'on', true);

  update public.profiles
     set role = v_invite.role,
         is_approved = true,
         updated_at = now()
   where id = v_uid;

  update public.invites
     set uses = uses + 1, updated_at = now()
   where id = v_invite.id;

  return v_invite.role;
end;
$$;

revoke all on function public.redeem_invite(text) from public, anon;
grant execute on function public.redeem_invite(text) to authenticated;

-- -------------------------------------------------------------------------
-- 3. create_invite — aceita p_max_uses null (ilimitado) e traduz a colisão
--    de código em um erro que o app sabe explicar.
--
-- Sem o handler de unique_violation o admin recebia "duplicate key value
-- violates unique constraint invites_code_key", que vaza nome de índice na
-- tela e não diz o que fazer.
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

  if p_max_uses is not null and p_max_uses <= 0 then
    raise exception 'INVALID_MAX_USES';
  end if;

  -- Se o código não foi fornecido, gera um aleatório sem 0/O/1/I.
  -- string_agg é agregação (não janela), então vai num subselect com
  -- generate_series como fonte de linhas.
  v_code := coalesce(
    nullif(upper(trim(p_code)), ''),
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
exception
  when unique_violation then
    raise exception 'INVITE_CODE_TAKEN';
end;
$$;

revoke all on function public.create_invite(public.app_role, integer, timestamptz, text, text) from public, anon;
grant execute on function public.create_invite(public.app_role, integer, timestamptz, text, text) to authenticated;

-- -------------------------------------------------------------------------
-- 4. update_invite — edição de um convite existente pelo admin.
--
-- Semântica de SUBSTITUIÇÃO TOTAL, não de patch: todo parâmetro nulo grava
-- nulo (sem limite / sem validade / sem observação). É o que a tela faz —
-- abre o formulário preenchido com o valor atual e devolve o estado inteiro.
-- Um patch parcial exigiria um sentinela por campo para distinguir "não
-- mexer" de "limpar", e isso já mordeu o cache local antes (ver AGENTS.md,
-- `insertOnConflictUpdate` com nullToAbsent).
--
-- `uses` NÃO é editável: é o contador de resgates, não uma configuração.
-- Baixar o limite para menos que os usos já feitos é permitido e simplesmente
-- deixa o convite esgotado — que é a forma de fechar um convite sem revogá-lo.
-- -------------------------------------------------------------------------
create or replace function public.update_invite(
  p_invite_id uuid,
  p_code text,
  p_role public.app_role default 'obreiro',
  p_max_uses integer default null,
  p_expires_at timestamptz default null,
  p_note text default null
)
returns public.invites
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := nullif(upper(trim(coalesce(p_code, ''))), '');
  v_invite public.invites;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN_NOT_ADMIN';
  end if;

  if v_code is null then
    raise exception 'INVALID_INVITE_CODE';
  end if;

  if p_max_uses is not null and p_max_uses <= 0 then
    raise exception 'INVALID_MAX_USES';
  end if;

  update public.invites
     set code = v_code,
         role = p_role,
         max_uses = p_max_uses,
         expires_at = p_expires_at,
         note = p_note,
         updated_at = now()
   where id = p_invite_id
     and deleted_at is null
  returning * into v_invite;

  if not found then
    raise exception 'INVITE_NOT_FOUND';
  end if;

  return v_invite;
exception
  when unique_violation then
    raise exception 'INVITE_CODE_TAKEN';
end;
$$;

revoke all on function public.update_invite(uuid, text, public.app_role, integer, timestamptz, text) from public, anon;
grant execute on function public.update_invite(uuid, text, public.app_role, integer, timestamptz, text) to authenticated;
