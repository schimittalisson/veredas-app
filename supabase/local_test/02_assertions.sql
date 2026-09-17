-- =========================================================================
-- Asserções de RLS. Cada linha imprime PASS ou FAIL.
-- O run.sh conta os FAIL e usa isso como exit code.
--
-- Não use `psql -q` para rodar: as mensagens saem por RAISE NOTICE.
-- =========================================================================

-- -------------------------------------------------------------------------
-- Helpers. São security definer porque precisam trocar de role e ler
-- catálogos; nunca vão para o banco de produção (só o harness os aplica).
-- -------------------------------------------------------------------------
create schema if not exists test;

-- Simula um usuário autenticado dentro da transação corrente.
create or replace function test.act_as(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true                                  -- is_local: morre no fim da tx
  );
  execute 'set local role authenticated';
end;
$$;

-- Compara um count com o esperado.
create or replace function test.expect_count(
  p_label text, p_sql text, p_expected bigint
)
returns void
language plpgsql
as $$
declare v bigint;
begin
  execute p_sql into v;
  if v = p_expected then
    raise notice 'PASS  % (=%)', p_label, v;
  else
    raise notice 'FAIL  % -> obtido %, esperado %', p_label, v, p_expected;
  end if;
end;
$$;

-- Espera que a escrita seja NEGADA (por RLS ou por trigger).
create or replace function test.expect_denied(p_label text, p_sql text)
returns void
language plpgsql
as $$
begin
  execute p_sql;
  raise notice 'FAIL  % -> a escrita foi PERMITIDA', p_label;
exception
  when insufficient_privilege then
    raise notice 'PASS  % (RLS negou)', p_label;
  when raise_exception then
    raise notice 'PASS  % (trigger negou: %)', p_label, sqlerrm;
end;
$$;

-- Espera que a escrita seja recusada por um CHECK CONSTRAINT (23514).
--
-- Separado de expect_denied de propósito: aquele captura 42501 (RLS) e P0001
-- (trigger). Se ele também aceitasse 23514, uma asserção de permissão passaria
-- por engano quando o insert falhasse por um motivo sem relação com RLS —
-- perderíamos justamente a precisão que faz o teste valer.
create or replace function test.expect_check_violation(p_label text, p_sql text)
returns void
language plpgsql
as $$
begin
  execute p_sql;
  raise notice 'FAIL  % -> a escrita foi PERMITIDA', p_label;
exception
  when check_violation then
    raise notice 'PASS  % (check recusou)', p_label;
end;
$$;

-- Espera que a escrita seja PERMITIDA.
create or replace function test.expect_allowed(p_label text, p_sql text)
returns void
language plpgsql
as $$
begin
  execute p_sql;
  raise notice 'PASS  %', p_label;
exception
  when others then
    raise notice 'FAIL  % -> negado: % (%)', p_label, sqlerrm, sqlstate;
end;
$$;

-- Espera que um UPDATE afete exatamente N linhas (RLS filtra sem erro).
create or replace function test.expect_rowcount(
  p_label text, p_sql text, p_expected integer
)
returns void
language plpgsql
as $$
declare n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n = p_expected then
    raise notice 'PASS  % (% linha(s))', p_label, n;
  else
    raise notice 'FAIL  % -> % linha(s), esperado %', p_label, n, p_expected;
  end if;
end;
$$;

-- Os helpers rodam como SECURITY INVOKER de propósito: precisam executar com o
-- role `authenticated` para que o RLS realmente se aplique dentro deles. Como
-- act_as() troca o role, o schema `test` tem de ser alcançável por ele.
grant usage on schema test to authenticated, anon;
grant execute on all functions in schema test to authenticated, anon;

\set nao_aprovado '11111111-1111-1111-1111-111111111111'
\set gerente      '22222222-2222-2222-2222-222222222222'
\set comum        '33333333-3333-3333-3333-333333333333'

\echo ''
\echo '=========== 1. Usuario NAO APROVADO nao ve nada ==========='
begin;
  select test.act_as(:'nao_aprovado');
  select test.expect_count('nao aprovado: events',            'select count(*) from public.events', 0);
  select test.expect_count('nao aprovado: scale_assignments',  'select count(*) from public.scale_assignments', 0);
  select test.expect_count('nao aprovado: prayer_posts',       'select count(*) from public.prayer_posts', 0);
  select test.expect_count('nao aprovado: scale_types',        'select count(*) from public.scale_types', 0);
  select test.expect_count('nao aprovado: weekly_slots',       'select count(*) from public.weekly_slots', 0);
  select test.expect_count('nao aprovado: base_info',          'select count(*) from public.base_info', 0);
  select test.expect_count('nao aprovado: social_links',       'select count(*) from public.social_links', 0);
  select test.expect_count('nao aprovado: documents',          'select count(*) from public.documents', 0);
  -- Precisa ver o proprio perfil, senao a tela /aguardando fica em limbo.
  select test.expect_count('nao aprovado: ve o proprio perfil','select count(*) from public.profiles', 1);
rollback;

\echo ''
\echo '=========== 2. Obreiro APROVADO le o conteudo ==========='
begin;
  select test.act_as(:'comum');
  -- 6 desde a migration 20260917000100, que acrescentou a escala de Almoço.
  select test.expect_count('obreiro: scale_types',   'select count(*) from public.scale_types', 6);
  select test.expect_count('obreiro: weekly_slots',  'select count(*) from public.weekly_slots', 40);
  select test.expect_count('obreiro: base_info',     'select count(*) from public.base_info', 4);
  select test.expect_count('obreiro: social_links',  'select count(*) from public.social_links', 3);
  select test.expect_count('obreiro: prayer_feed',   'select count(*) from public.prayer_feed', 1);
  -- Convites sao so do admin: um obreiro nao pode enumerar codigos validos.
  select test.expect_count('obreiro: NAO ve convites','select count(*) from public.invites', 0);
rollback;

\echo ''
\echo '=========== 3. Escalas: o requisito central do app ==========='
begin;
  select test.act_as(:'comum');
  select test.expect_denied(
    'obreiro comum NAO escala em servir-ao-todo',
    $q$insert into public.scale_assignments (scale_type_id, starts_on, assignee_name)
       values ((select id from public.scale_types where slug='servir-ao-todo'),
               current_date, 'Teste')$q$);
rollback;

begin;
  select test.act_as(:'gerente');
  select test.expect_allowed(
    'responsavel ESCALA em servir-ao-todo (a sua)',
    $q$insert into public.scale_assignments (scale_type_id, starts_on, assignee_name)
       values ((select id from public.scale_types where slug='servir-ao-todo'),
               current_date, 'Teste')$q$);
rollback;

begin;
  select test.act_as(:'gerente');
  select test.expect_denied(
    'responsavel NAO escala em lixo (nao e a sua)',
    $q$insert into public.scale_assignments (scale_type_id, starts_on, assignee_name)
       values ((select id from public.scale_types where slug='lixo'),
               current_date, 'Teste')$q$);
rollback;

-- Equipe na mesma atribuicao (migration 20260917000100). O CHECK
-- assignment_has_someone precisa aceitar a linha que so tem equipe: uma escala
-- de quatro pessoas sem responsavel geral e o caso normal do almoco.
begin;
  select test.act_as(:'gerente');
  select test.expect_allowed(
    'responsavel escala EQUIPE sem responsavel geral',
    $q$insert into public.scale_assignments
         (scale_type_id, starts_on, member_names)
       values ((select id from public.scale_types where slug='servir-ao-todo'),
               current_date, array['Ana','Bia','Caio','Dan'])$q$);
rollback;

begin;
  select test.act_as(:'gerente');
  select test.expect_check_violation(
    'atribuicao sem ninguem e recusada pelo check',
    $q$insert into public.scale_assignments (scale_type_id, starts_on)
       values ((select id from public.scale_types where slug='servir-ao-todo'),
               current_date)$q$);
rollback;

-- Administração das escalas pelo app (tela /admin/escalas). A tela é guardada
-- por um redirect, mas quem decide e o RLS: um APK modificado chega aqui.
begin;
  select test.act_as(:'gerente');
  select test.expect_denied(
    'obreiro NAO cria tipo de escala',
    $q$insert into public.scale_types (slug, name, cadence)
       values ('jardim', 'Jardim', 'weekly')$q$);
rollback;

begin;
  select test.act_as(:'gerente');
  select test.expect_rowcount(
    'obreiro NAO renomeia escala (RLS filtra, 0 linhas)',
    $q$update public.scale_types set name='Renomeada' where slug='lixo'$q$, 0);
  select test.expect_rowcount(
    'obreiro NAO reordena escala (0 linhas)',
    $q$update public.scale_types set ordering=99 where slug='lixo'$q$, 0);
rollback;

begin;
  select test.act_as(:'gerente');
  select test.expect_denied(
    'obreiro NAO se nomeia responsavel de lixo',
    $q$insert into public.scale_managers (scale_type_id, user_id)
       values ((select id from public.scale_types where slug='lixo'),
               '22222222-2222-2222-2222-222222222222')$q$);
rollback;

\echo ''
\echo '=========== 4. Escalada de privilegio ==========='
begin;
  select test.act_as(:'gerente');
  select test.expect_denied(
    'obreiro NAO se promove a admin',
    $q$update public.profiles set role='admin'
        where id='22222222-2222-2222-2222-222222222222'$q$);
rollback;

begin;
  select test.act_as(:'nao_aprovado');
  select test.expect_denied(
    'nao aprovado NAO se auto-aprova',
    $q$update public.profiles set is_approved=true
        where id='11111111-1111-1111-1111-111111111111'$q$);
rollback;

\echo ''
\echo '=========== 5. Resgate de convite ==========='
-- Complementar ao bloco 4: o obreiro nao pode se promover, MAS o convite tem
-- de funcionar. Se apenas um dos dois passar, a flag app.redeeming_invite
-- da migration 0800 esta errada.
begin;
  select test.act_as(:'nao_aprovado');
  select test.expect_count(
    'convite valido aprova o usuario',
    $q$select count(*) from (select public.redeem_invite('VEREDAS2026')) s$q$, 1);
  select test.expect_count(
    'apos resgate, is_approved = true',
    $q$select count(*) from public.profiles
        where id='11111111-1111-1111-1111-111111111111' and is_approved$q$, 1);
rollback;

begin;
  select test.act_as(:'nao_aprovado');
  select test.expect_denied(
    'codigo inexistente e rejeitado',
    $q$select public.redeem_invite('CODIGO-QUE-NAO-EXISTE')$q$);
rollback;

begin;
  select test.act_as(:'nao_aprovado');
  select test.expect_allowed(
    'codigo em minusculas funciona (case-insensitive)',
    $q$select public.redeem_invite('veredas2026')$q$);
rollback;

begin;
  select test.act_as(:'nao_aprovado');
  select public.redeem_invite('VEREDAS2026');
  select public.redeem_invite('VEREDAS2026');
  reset role;
  -- Idempotente: dois resgates do mesmo usuario nao gastam duas vagas.
  select test.expect_count('resgate repetido nao gasta 2 usos',
    $q$select uses from public.invites where code='VEREDAS2026'$q$, 1);
rollback;

\echo ''
\echo '=========== 6. Mural de oracao ==========='
begin;
  select test.act_as(:'gerente');
  select test.expect_rowcount(
    'obreiro NAO edita post de outro (RLS filtra)',
    $q$update public.prayer_posts set body='invadido'
        where id='44444444-4444-4444-4444-444444444444'$q$, 0);
rollback;

begin;
  select test.act_as(:'comum');
  select test.expect_rowcount(
    'autor edita o proprio post',
    $q$update public.prayer_posts set body='editado pelo autor'
        where id='44444444-4444-4444-4444-444444444444'$q$, 1);
rollback;

begin;
  select test.act_as(:'nao_aprovado');
  select test.expect_denied(
    'nao aprovado NAO publica',
    $q$insert into public.prayer_posts (author_id,title,body)
       values ('11111111-1111-1111-1111-111111111111','Teste','Corpo')$q$);
rollback;

begin;
  select test.act_as(:'gerente');
  select test.expect_denied(
    'obreiro NAO publica em nome de outro',
    $q$insert into public.prayer_posts (author_id,title,body)
       values ('33333333-3333-3333-3333-333333333333','Falso','Corpo')$q$);
rollback;

\echo ''
\echo '=========== 7. Tela Inicio: so admin escreve ==========='
begin;
  select test.act_as(:'gerente');
  select test.expect_denied(
    'obreiro NAO cria aviso',
    $q$insert into public.announcements (author_id, body)
       values ('22222222-2222-2222-2222-222222222222','Aviso indevido')$q$);
  -- ATENCAO a semantica do RLS aqui, ela importa para o OutboxWorker (Fase 4):
  -- num UPDATE/DELETE, as linhas que reprovam no USING sao FILTRADAS em
  -- silencio (0 linhas), NAO geram erro. Só o WITH CHECK (INSERT, ou UPDATE que
  -- produza linha proibida) lança 42501. Ou seja: uma escrita negada pelo RLS
  -- volta 200 com 0 linhas, nao 403.
  select test.expect_rowcount(
    'obreiro NAO edita dados da base (RLS filtra, 0 linhas)',
    $q$update public.base_info set value='hackeado' where key='cep'$q$, 0);
  select test.expect_rowcount(
    'obreiro NAO exclui dados da base',
    $q$delete from public.base_info where key='cep'$q$, 0);
  select test.expect_denied(
    'obreiro NAO cria item em dados da base (WITH CHECK -> erro)',
    $q$insert into public.base_info (key,label,value)
       values ('pix','PIX','x')$q$);
  -- Garante que o valor realmente nao mudou, e nao apenas que a contagem bateu.
  select test.expect_count(
    'valor de base_info intacto apos as tentativas',
    $q$select count(*) from public.base_info
        where key='cep' and value='89204-620'$q$, 1);
rollback;

\echo ''
\echo '=========== 7b. Arquivos (documents) ==========='
-- O catálogo é publicado pela liderança e lido por todo aprovado. As duas
-- pontas importam: se a leitura vazasse para não aprovado, um cadastro pendente
-- veria material interno; se a escrita vazasse, qualquer obreiro mudaria o link
-- de um treinamento para onde quisesse.
begin;
  -- Promove o gerente a admin, mesmo caminho da seção 9.
  update public.profiles set role='admin', is_approved=true
   where id = :'gerente';

  select test.act_as(:'gerente');
  select test.expect_allowed('admin cadastra arquivo',
    $q$insert into public.documents (id, title, source_type, url)
       values ('dddddddd-dddd-dddd-dddd-dddddddddddd','Manual de discipulado',
               'link','https://drive.google.com/file/abc')$q$);
  reset role;

  select test.act_as(:'comum');
  select test.expect_count('obreiro aprovado LE os arquivos',
    $q$select count(*) from public.documents$q$, 1);
  select test.expect_denied(
    'obreiro NAO cadastra arquivo',
    $q$insert into public.documents (title, source_type, url)
       values ('Indevido','link','https://x.org/a')$q$);
  select test.expect_rowcount(
    'obreiro NAO edita arquivo (RLS filtra, 0 linhas)',
    $q$update public.documents set url='https://malicioso.org'
        where title='Manual de discipulado'$q$, 0);
  select test.expect_rowcount(
    'obreiro NAO exclui arquivo',
    $q$delete from public.documents$q$, 0);
  reset role;

  select test.act_as(:'nao_aprovado');
  select test.expect_count('nao aprovado NAO ve arquivo algum',
    $q$select count(*) from public.documents$q$, 0);
  reset role;

  -- O soft delete é o que faz o item desaparecer para todos: o app manda um
  -- UPDATE de deleted_at, e a policy de leitura filtra. Se este teste falhar, um
  -- arquivo "excluído" continuaria aparecendo.
  select test.act_as(:'gerente');
  select test.expect_rowcount('admin exclui via deleted_at',
    $q$update public.documents set deleted_at = now()
        where title='Manual de discipulado'$q$, 1);
  reset role;

  select test.act_as(:'comum');
  select test.expect_count('arquivo excluido desaparece para o obreiro',
    $q$select count(*) from public.documents$q$, 0);
rollback;

-- O check constraint impede uma linha sem destino, que apareceria na lista como
-- um item que simplesmente não abre.
begin;
  update public.profiles set role='admin', is_approved=true
   where id = :'gerente';
  select test.act_as(:'gerente');
  select test.expect_check_violation(
    'atalho sem url e rejeitado pelo check',
    $q$insert into public.documents (title, source_type)
       values ('Sem destino','link')$q$);
  select test.expect_check_violation(
    'arquivo sem storage_path e rejeitado pelo check',
    $q$insert into public.documents (title, source_type, url)
       values ('Sem caminho','file','https://x.org/a')$q$);
rollback;

\echo ''
\echo '=========== 8. Busca ignora acento e caixa ==========='
begin;
  select test.act_as(:'comum');
  select test.expect_count('busca "cura" acha "Cura"',
    $q$select count(*) from public.search_prayers('cura')$q$, 1);
  select test.expect_count('busca "CURA" (caixa alta)',
    $q$select count(*) from public.search_prayers('CURA')$q$, 1);
  select test.expect_count('busca "curá" (com acento)',
    $q$select count(*) from public.search_prayers('curá')$q$, 1);
  select test.expect_count('busca "mae" acha "mãe"',
    $q$select count(*) from public.search_prayers('mae')$q$, 1);
  select test.expect_count('busca no corpo ("internada")',
    $q$select count(*) from public.search_prayers('internada')$q$, 1);
  select test.expect_count('termo inexistente nao acha nada',
    $q$select count(*) from public.search_prayers('xyzzy')$q$, 0);
rollback;

\echo ''
\echo '=========== 9. Bootstrap do admin (README passo 7) ==========='
-- auth.uid() e NULL aqui: acesso direto ao banco. Sem a excecao no trigger da
-- migration 0800 este UPDATE falha e NAO existe forma de criar o 1o admin.
begin;
  select test.expect_rowcount(
    'promover 1o admin pelo SQL Editor',
    $q$update public.profiles set role='admin', is_approved=true
        where email='gerente@teste.com'$q$, 1);

  select test.act_as(:'gerente');
  select test.expect_allowed(
    'admin escala em QUALQUER escala',
    $q$insert into public.scale_assignments (scale_type_id, starts_on, assignee_name)
       values ((select id from public.scale_types where slug='lixo'),
               current_date, 'Admin pode')$q$);
  select test.expect_count('admin VE convites',
    $q$select count(*) from public.invites$q$, 1);
  select test.expect_allowed('admin cria aviso',
    $q$insert into public.announcements (author_id, body)
       values ('22222222-2222-2222-2222-222222222222','Aviso do admin')$q$);
  select test.expect_allowed('admin cria tipo de escala',
    $q$insert into public.scale_types (slug, name, cadence, ordering)
       values ('jardim', 'Jardim', 'weekly', 9)$q$);
  select test.expect_allowed('admin renomeia e reordena escala',
    $q$update public.scale_types set name='Almoco da base', ordering=4
        where slug='almoco'$q$);
  select test.expect_allowed('admin exclui escala por deleted_at',
    $q$update public.scale_types set deleted_at=now() where slug='almoco'$q$);
  select test.expect_allowed('admin define responsavel de escala',
    $q$insert into public.scale_managers (scale_type_id, user_id)
       values ((select id from public.scale_types where slug='lixo'),
               '33333333-3333-3333-3333-333333333333')$q$);
  select test.expect_allowed('admin aprova outro obreiro',
    $q$update public.profiles set is_approved=true, role='obreiro'
        where id='33333333-3333-3333-3333-333333333333'$q$);
rollback;

\echo ''
\echo '=========== 11. Excluir a conta nao apaga a escala do grupo ==========='
-- O caso que a migration 20260917000100 teve de resolver: antes das equipes,
-- uma atribuicao era de uma pessoa so, e derrubar a linha inteira era correto.
-- Com grupo, derrubar a linha tiraria as outras tres pessoas da escala junto.
begin;
  insert into public.scale_assignments (id, scale_type_id, starts_on, member_ids)
  values
    -- futura, em grupo: tem de sobreviver sem o uid de quem saiu
    ('55555555-5555-5555-5555-555555555555',
     (select id from public.scale_types where slug='almoco'),
     current_date + 7,
     array[:'comum'::uuid, :'gerente'::uuid]),
    -- futura, so dele: vira tombstone, como antes
    ('66666666-6666-6666-6666-666666666666',
     (select id from public.scale_types where slug='almoco'),
     current_date + 7,
     array[:'comum'::uuid]),
    -- passada: fica como registro historico, sem identificar a pessoa
    ('77777777-7777-7777-7777-777777777777',
     (select id from public.scale_types where slug='almoco'),
     current_date - 7,
     array[:'comum'::uuid, :'gerente'::uuid]);

  select test.act_as(:'comum');
  select public.delete_own_account();
  reset role;

  -- O RPC acima falhava com FORBIDDEN_PRIVILEGE_CHANGE para quem não é admin
  -- (o trigger recusava o `is_approved = false` do próprio perfil). Corrigido
  -- na migration 20260917000200.
  select test.expect_count('obreiro comum exclui a propria conta',
    $q$select count(*) from public.profiles
        where id='33333333-3333-3333-3333-333333333333'
          and deleted_at is not null
          and not is_approved
          and full_name = 'Removido'$q$, 1);
  select test.expect_count('escala futura do grupo sobrevive',
    $q$select count(*) from public.scale_assignments
        where id='55555555-5555-5555-5555-555555555555'
          and deleted_at is null
          and member_ids = array['22222222-2222-2222-2222-222222222222'::uuid]$q$, 1);
  select test.expect_count('escala futura so dele vira tombstone',
    $q$select count(*) from public.scale_assignments
        where id='66666666-6666-6666-6666-666666666666'
          and deleted_at is not null$q$, 1);
  select test.expect_count('escala passada troca o uid por "Removido"',
    $q$select count(*) from public.scale_assignments
        where id='77777777-7777-7777-7777-777777777777'
          and deleted_at is null
          and not (member_ids @> array['33333333-3333-3333-3333-333333333333'::uuid])
          and member_names @> array['Removido']$q$, 1);
rollback;

\echo ''
\echo '=========== 10. Nenhuma tabela publica sem RLS ==========='
select test.expect_count(
  'tabelas public sem RLS',
  $q$select count(*) from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname='public' and c.relkind='r' and not c.relrowsecurity$q$, 0);
