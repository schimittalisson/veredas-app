-- =========================================================================
-- §9 — Seeds
--
-- Reaplicável: rodar duas vezes não duplica nem sobrescreve nada.
-- Valores marcados com TODO precisam ser trocados pelos dados reais da base
-- antes de ir para produção (o app exibe literalmente "TODO" na tela Início).
-- =========================================================================

-- ---- Tipos de escala ----
-- São dados, não código: a TabBar da tela Escalas é gerada daqui. Adicionar
-- uma escala nova é um INSERT, não um release do app.
insert into public.scale_types (slug, name, description, icon, cadence, slots, ordering)
values
  ('servir-ao-todo', 'Servir ao Todo',
   'Limpeza e manutenção das áreas da base.', 'cleaning_services', 'weekly',
   array['Cozinha','Banheiros','Área comum','Pátio'], 1),

  ('lixo', 'Lixo',
   'Recolhimento e descarte do lixo.', 'delete_outline', 'weekly',
   array[]::text[], 2),

  ('cafe-da-manha', 'Café da Manhã',
   'Preparo do café da manhã da base.', 'free_breakfast', 'weekly',
   array['Preparo','Louça'], 3),

  ('intercessoes', 'Intercessões',
   'Turnos de intercessão.', 'volunteer_activism', 'weekly',
   array['06:00-07:00','12:00-13:00','18:00-19:00','21:00-22:00'], 4),

  ('cafe-da-gratidao', 'Café da Gratidão',
   'Escala do Café da Gratidão.', 'celebration', 'adhoc',
   array[]::text[], 5)
on conflict (slug) do nothing;

-- ---- Dados da base (TODO: valores reais) ----
insert into public.base_info (key, label, value, ordering) values
  ('endereco', 'Endereço da base', 'TODO', 1),
  ('cep',      'CEP',              'TODO', 2),
  ('telefone', 'Telefone',         'TODO', 3),
  ('cnpj',     'CNPJ',             'TODO', 4)
on conflict (key) do nothing;

-- ---- Redes sociais (TODO: URLs reais) ----
-- O índice único em platform (migration 0400) é o que torna isto idempotente.
insert into public.social_links (platform, url, ordering) values
  ('instagram', 'https://instagram.com/TODO', 1),
  ('facebook',  'https://facebook.com/TODO',  2),
  ('youtube',   'https://youtube.com/@TODO',  3)
on conflict (platform) do nothing;

-- ---- Cronograma semanal (TODO: cronograma real da base) ----
-- weekday: 1 = segunda ... 7 = domingo (ISO-8601, igual a DateTime.weekday).
-- weekly_slots não tem chave natural (a base pode ter dois eventos no mesmo
-- horário), então a idempotência vem de um guard explícito em vez de
-- `on conflict`, que nunca dispararia.
insert into public.weekly_slots (weekday, starts_at, ends_at, title, location)
select * from (values
  (1::smallint, '06:00'::time, '07:00'::time, 'Intercessão',     'Sala de oração'),
  (1::smallint, '08:00'::time, '09:00'::time, 'Café da manhã',   'Cozinha'),
  (3::smallint, '19:30'::time, '21:00'::time, 'Culto de oração', 'Salão')
) as v(weekday, starts_at, ends_at, title, location)
where not exists (
  select 1 from public.weekly_slots w
   where w.weekday = v.weekday
     and w.starts_at = v.starts_at
     and w.title = v.title
);

-- ---- Convite inicial ----
-- max_uses 20 = um por obreiro da base. O índice único é em upper(code).
insert into public.invites (code, role, max_uses, note)
values ('VEREDAS2026', 'obreiro', 20, 'Convite inicial dos obreiros')
on conflict do nothing;
