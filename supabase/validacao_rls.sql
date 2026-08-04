-- =========================================================================
-- §11 — Roteiro de validação do RLS (aceite da Fase 1)
--
-- Execute no SQL Editor do Supabase, um bloco por vez.
-- `set local role authenticated` + `request.jwt.claims` simulam um usuário
-- logado, sem precisar de app rodando.
--
-- Todo bloco termina em `rollback`: nada é persistido.
--
-- Os 5 blocos precisam se comportar EXATAMENTE como anotado. Se algum
-- divergir, NÃO avance para a Fase 2 — corrija a policy primeiro. Este é o
-- momento em que a segurança do app é decidida.
--
-- ANTES DE RODAR: crie 3 contas de teste pelo app (ou pelo painel Auth) e
-- substitua os UUIDs abaixo. Pegue os UUIDs com:
--   select id, email, is_approved, role from public.profiles;
--
--   <uuid_nao_aprovado> - cadastrado, convite NÃO resgatado
--   <uuid_obreiro>      - aprovado, e inserido em scale_managers p/ servir-ao-todo
--   <uuid_outro>        - aprovado, não gerencia nada
--
-- Para preparar o obreiro gerente (rode uma vez, fora dos blocos):
--   insert into public.scale_managers (scale_type_id, user_id)
--   values ((select id from public.scale_types where slug = 'servir-ao-todo'),
--           '<uuid_obreiro>');
-- =========================================================================


-- =========================================================================
-- BLOCO 1 — Usuário não aprovado não vê NADA além do próprio perfil.
-- =========================================================================
begin;
  set local role authenticated;
  set local "request.jwt.claims" = '{"sub":"<uuid_nao_aprovado>","role":"authenticated"}';

  -- ESPERADO: 0
  select count(*) as eventos_deve_ser_zero  from public.events;
  -- ESPERADO: 0
  select count(*) as escalas_deve_ser_zero  from public.scale_assignments;
  -- ESPERADO: 0
  select count(*) as oracoes_deve_ser_zero  from public.prayer_posts;
  -- ESPERADO: 1  (vê só o próprio perfil, via profiles_select_self)
  select count(*) as perfis_deve_ser_um     from public.profiles;
rollback;


-- =========================================================================
-- BLOCO 2 — Obreiro aprovado que não gerencia escala NÃO pode inserir.
-- =========================================================================
begin;
  set local role authenticated;
  set local "request.jwt.claims" = '{"sub":"<uuid_outro>","role":"authenticated"}';

  -- ESPERADO: erro
  --   new row violates row-level security policy for table "scale_assignments"
  insert into public.scale_assignments (scale_type_id, starts_on, assignee_name)
  values ((select id from public.scale_types where slug = 'servir-ao-todo'),
          current_date, 'Teste');
rollback;


-- =========================================================================
-- BLOCO 3 — Responsável escreve na SUA escala e falha nas outras.
-- Este é o requisito central do app. Rode as duas metades separadamente:
-- a primeira deve passar, a segunda deve falhar.
-- =========================================================================

-- 3a) ESPERADO: sucesso (INSERT 0 1)
begin;
  set local role authenticated;
  set local "request.jwt.claims" = '{"sub":"<uuid_obreiro>","role":"authenticated"}';

  insert into public.scale_assignments (scale_type_id, starts_on, assignee_name)
  values ((select id from public.scale_types where slug = 'servir-ao-todo'),
          current_date, 'Teste');
rollback;

-- 3b) ESPERADO: erro de RLS (gerencia servir-ao-todo, NÃO gerencia lixo)
begin;
  set local role authenticated;
  set local "request.jwt.claims" = '{"sub":"<uuid_obreiro>","role":"authenticated"}';

  insert into public.scale_assignments (scale_type_id, starts_on, assignee_name)
  values ((select id from public.scale_types where slug = 'lixo'),
          current_date, 'Teste');
rollback;


-- =========================================================================
-- BLOCO 4 — Obreiro não consegue se promover a admin.
-- =========================================================================
begin;
  set local role authenticated;
  set local "request.jwt.claims" = '{"sub":"<uuid_obreiro>","role":"authenticated"}';

  -- ESPERADO: erro FORBIDDEN_PRIVILEGE_CHANGE (trigger da migration 0800)
  update public.profiles set role = 'admin' where id = '<uuid_obreiro>';
rollback;


-- =========================================================================
-- BLOCO 5 — ...MAS o resgate de convite funciona.
--
-- Os blocos 4 e 5 são complementares e AMBOS precisam passar. Se só um passar,
-- a flag transacional app.redeeming_invite (migration 0800) está errada:
--   - só o 4 passa  -> a flag não está liberando o trigger, ninguém se cadastra
--   - só o 5 passa  -> a flag está vazando, qualquer um vira admin
-- =========================================================================
begin;
  set local role authenticated;
  set local "request.jwt.claims" = '{"sub":"<uuid_nao_aprovado>","role":"authenticated"}';

  -- ESPERADO: retorna 'obreiro'
  select public.redeem_invite('VEREDAS2026') as papel_concedido;

  -- ESPERADO: is_approved = true, role = 'obreiro'
  select is_approved, role from public.profiles where id = '<uuid_nao_aprovado>';
rollback;


-- =========================================================================
-- BLOCO 6 — Sanidade: nenhuma tabela pública ficou sem RLS.
-- ESPERADO: 0 linhas. Qualquer linha aqui é um vazamento de dados.
-- =========================================================================
select c.relname as tabela_sem_rls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public'
   and c.relkind = 'r'
   and not c.relrowsecurity;
