-- Fixtures do harness de RLS. Ver local_test/README.md.
--
-- Reproduz só o que o Supabase ainda concede de fábrica: uso do schema e
-- execução de funções.
--
-- **Tabelas, não.** Desde 30/10/2026 o Supabase não dá mais acesso automático
-- a tabela nova do `public` pela Data API, e as migrations passaram a conceder
-- o próprio acesso (20261021000100 e seguintes). Antes este arquivo fazia
-- `grant all on all tables`, o que escondia justamente a migration que
-- esquecesse o grant: no harness tudo passava, e em produção a tabela
-- respondia "permission denied". A asserção §18 reprova tabela sem grant.
grant usage on schema public to anon, authenticated;
grant all on all routines  in schema public to anon, authenticated;

-- 3 usuários cobrindo os estados de permissão que importam.
-- O trigger on_auth_user_created cria os profiles correspondentes.
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'naoaprovado@teste.com', '{"full_name":"Nao Aprovado"}'),
  ('22222222-2222-2222-2222-222222222222', 'gerente@teste.com',     '{"full_name":"Obreiro Gerente"}'),
  ('33333333-3333-3333-3333-333333333333', 'comum@teste.com',       '{"full_name":"Obreiro Comum"}');

-- Aprova os dois últimos. Funciona porque auth.uid() é NULL aqui (acesso
-- direto ao banco), exceção documentada no trigger da migration 0800.
update public.profiles set is_approved = true
 where id in ('22222222-2222-2222-2222-222222222222',
              '33333333-3333-3333-3333-333333333333');

-- O "gerente" responde por servir-ao-todo, e só por ela.
insert into public.scale_managers (scale_type_id, user_id)
values ((select id from public.scale_types where slug = 'servir-ao-todo'),
        '22222222-2222-2222-2222-222222222222');

-- Post do obreiro comum, para testar edição alheia.
insert into public.prayer_posts (id, author_id, title, body) values
  ('44444444-4444-4444-4444-444444444444',
   '33333333-3333-3333-3333-333333333333',
   'Cura da minha mãe', 'Ela está internada desde terça.');

-- Aluno da ETED (papel 'aluno'), aprovado. E o obreiro comum como líder do
-- cronograma da ETED — o gerente, não, para os dois papéis não se misturarem.
insert into auth.users (id, email, raw_user_meta_data) values
  ('55555555-5555-5555-5555-555555555555', 'aluno@teste.com', '{"full_name":"Aluno ETED"}');
update public.profiles set is_approved = true, role = 'aluno'
 where id = '55555555-5555-5555-5555-555555555555';

insert into public.schedule_managers (schedule, user_id)
values ('eted', '33333333-3333-3333-3333-333333333333');
