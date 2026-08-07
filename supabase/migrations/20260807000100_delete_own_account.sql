-- =========================================================================
-- Exclusão da própria conta pelo usuário
-- =========================================================================
--
-- Exigência da Google Play: app que permite criar conta precisa oferecer um
-- caminho de exclusão dentro do próprio app. Até aqui só existia
-- `soft_delete_user`, que é `is_admin()` — um obreiro não conseguia sair.
--
-- -------------------------------------------------------------------------
-- Por que NÃO faz `delete from auth.users`
-- -------------------------------------------------------------------------
--
-- Seria tentador: `profiles.id → auth.users on delete cascade` derrubaria o
-- perfil e, por cascade, todo o conteúdo autoral numa linha só.
--
-- Mas isso quebraria o sync. `profiles`, `invites` e `scale_assignments` são
-- entidades **incrementais**: o pull filtra por `updated_at > marca d'água` e
-- descobre exclusões pelo tombstone `deleted_at`. Uma linha apagada
-- fisicamente simplesmente some — o cliente que sincroniza depois nunca fica
-- sabendo, e o cache dos outros aparelhos guardaria o obreiro removido para
-- sempre, até alguém reinstalar o app.
--
-- Então aqui tudo é soft delete, que é o que o mecanismo entende. O expurgo
-- físico de `auth.users` continua sendo passo manual do admin (mesma nota que
-- já existe em `soft_delete_user`), e é o único resíduo: o e-mail dentro do
-- schema `auth`, invisível para o app e inalcançável sem `service_role`.
--
-- O que o usuário perde na hora, conforme PRIVACIDADE.md §6:
--   - perfil: nome, e-mail, telefone, foto e bio são sobrescritos
--   - posts e comentários no mural
--   - escalas futuras
--   - convites que gerou e que ninguém usou
--
-- O que fica: escalas passadas, com o nome trocado por "Removido" — registro
-- histórico da base, sem identificar a pessoa.

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_active_admins integer;
  v_is_admin boolean;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select (role = 'admin' and is_approved and deleted_at is null)
    into v_is_admin
    from public.profiles
   where id = v_uid;

  if v_is_admin is null then
    raise exception 'USER_NOT_FOUND';
  end if;

  -- Mesma proteção de set_role e soft_delete_user: a base não pode ficar sem
  -- ninguém capaz de aprovar novos obreiros. O último admin passa o bastão
  -- antes de sair.
  if v_is_admin then
    select count(*) into v_active_admins
      from public.profiles
     where role = 'admin' and is_approved and deleted_at is null;

    if v_active_admins <= 1 then
      raise exception 'CANNOT_DELETE_LAST_ADMIN';
    end if;
  end if;

  -- Escalas futuras sob tombstone: quem saiu não continua escalado.
  update public.scale_assignments
     set deleted_at = now(),
         updated_at = now()
   where assignee_id = v_uid
     and starts_on >= current_date
     and deleted_at is null;

  -- Escalas passadas ficam, sem identificar a pessoa. O `assignee_id` vai a
  -- null e o nome vira "Removido" — nessa ordem numa única instrução, senão o
  -- CHECK `assignment_has_assignee` (exige id OU nome) reprovaria no meio.
  update public.scale_assignments
     set assignee_id = null,
         assignee_name = 'Removido',
         updated_at = now()
   where assignee_id = v_uid
     and deleted_at is null;

  -- Conteúdo autoral no mural.
  update public.prayer_posts
     set deleted_at = now(), updated_at = now()
   where author_id = v_uid and deleted_at is null;

  update public.prayer_comments
     set deleted_at = now(), updated_at = now()
   where author_id = v_uid and deleted_at is null;

  delete from public.prayer_interactions where user_id = v_uid;

  -- Convites que gerou e ninguém usou. Um convite já resgatado fica: apagá-lo
  -- destruiria o rastro de como outra pessoa entrou na base.
  update public.invites
     set deleted_at = now(), updated_at = now()
   where created_by = v_uid
     and uses = 0
     and deleted_at is null;

  -- Deixa de ser responsável por qualquer escala.
  delete from public.scale_managers where user_id = v_uid;

  -- O perfil por último: sobrescreve o que identifica a pessoa e marca o
  -- tombstone, que é o que os outros aparelhos vão receber no próximo pull.
  update public.profiles
     set full_name = 'Removido',
         email = null,
         phone = null,
         avatar_url = null,
         bio = null,
         is_approved = false,
         deleted_at = now(),
         updated_at = now()
   where id = v_uid;
end;
$$;

-- `anon` não pode chamar: sem sessão não há conta para apagar, e expor isto
-- ao público seria superfície de ataque sem propósito.
revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;

comment on function public.delete_own_account() is
  'Apaga a conta do usuário autenticado e o conteúdo dele, por soft delete. '
  'Exigência da Google Play para apps com cadastro. Ver PRIVACIDADE.md §6.';
