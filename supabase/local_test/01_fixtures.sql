-- Fixtures do harness de RLS. Ver local_test/README.md.
--
-- Reproduz os grants que o Supabase aplica de fábrica ao role `authenticated`.
-- Sem eles os testes falhariam por falta de GRANT, e não por RLS — o que
-- mascararia exatamente o que queremos medir.
grant usage on schema public to anon, authenticated;
grant all on all tables    in schema public to anon, authenticated;
grant all on all sequences in schema public to anon, authenticated;
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
