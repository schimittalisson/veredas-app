-- =========================================================================
-- §5 — Views e RPCs
-- =========================================================================

-- -------------------------------------------------------------------------
-- Feed de oração com contadores agregados.
--
-- security_invoker = true faz a view respeitar o RLS de QUEM CONSULTA.
-- Sem isso a view rodaria com os privilégios do owner e vazaria os posts
-- para usuários não aprovados. Não remova.
--
-- O cache local do app espelha ESTA VIEW, não prayer_posts — porque
-- praying_count / is_praying vêm daqui e prayer_interactions não é cacheada
-- (ver SCHEMA.md "Estratégia de sincronização por tabela").
-- -------------------------------------------------------------------------
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
where p.deleted_at is null;

grant select on public.prayer_feed to authenticated;

-- -------------------------------------------------------------------------
-- Busca por título (e corpo), ignorando acento e caixa.
-- Usa os índices trigram criados na 0400.
-- -------------------------------------------------------------------------
create or replace function public.search_prayers(
  p_term text,
  p_limit integer default 30,
  p_offset integer default 0
)
returns setof public.prayer_feed
language sql
stable
security invoker
set search_path = public
as $$
  select * from public.prayer_feed
   where public.norm_text(title) like '%' || public.norm_text(p_term) || '%'
      or public.norm_text(body)  like '%' || public.norm_text(p_term) || '%'
   order by created_at desc
   limit least(coalesce(p_limit, 30), 100) offset coalesce(p_offset, 0);
$$;

grant execute on function public.search_prayers(text, integer, integer) to authenticated;

-- -------------------------------------------------------------------------
-- Resgate de convite. É o portão de entrada do app: transforma um usuário
-- recém-registrado (is_approved = false) em obreiro aprovado.
--
-- security definer porque o usuário NÃO tem permissão de update no próprio
-- role/is_approved — senão qualquer um se promoveria a admin.
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
  if v_invite.uses >= v_invite.max_uses then raise exception 'INVITE_EXHAUSTED'; end if;

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
