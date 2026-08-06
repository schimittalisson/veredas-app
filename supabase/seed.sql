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

  ('intercessoes', 'Intercessão',
   'Turnos de intercessão.', 'volunteer_activism', 'weekly',
   array['06:00-07:00','12:00-13:00','18:00-19:00','21:00-22:00'], 4),

  ('cafe-da-gratidao', 'Café da Gratidão',
   'Escala do Café da Gratidão.', 'celebration', 'adhoc',
   array[]::text[], 5)
on conflict (slug) do nothing;

-- ---- Dados da base ----
insert into public.base_info (key, label, value, ordering) values
  ('endereco', 'Endereço da base', 'R. Padre Anchieta, 97 - Glória, Joinville - SC', 1),
  ('cep',      'CEP',              '89204-620', 2),
  ('telefone', 'Telefone',         '(47) 3085-7873', 3),
  ('cnpj',     'CNPJ',             '59.944.890/0001-32', 4)
on conflict (key) do nothing;

-- ---- Redes sociais ----
-- O índice único em platform (migration 0400) é o que torna isto idempotente.
insert into public.social_links (platform, url, ordering) values
  ('instagram', 'https://instagram.com/jocumveredas/', 1),
  ('facebook',  'https://facebook.com/jocumveredas',  2),
  ('youtube',   'https://youtube.com/@jocumveredas3649',  3)
on conflict (platform) do nothing;

-- ---- Cronograma semanal (PONTO DE PARTIDA — editável no app) ----
--
-- ATENÇÃO: este cronograma é um MODELO, não o cronograma real da base. Ele
-- segue o ritmo típico de uma base JOCUM (intercessão de manhã, refeições
-- comunitárias, aulas, serviço, evangelismo), para que a aba Cronograma não
-- nasça vazia e os admins tenham algo concreto para ajustar.
--
-- Os admins editam tudo pela tela `/cronograma/:id/editar` (Fase 6). Não é
-- preciso mexer em SQL para corrigir um horário.
--
-- weekday: 1 = segunda ... 7 = domingo (ISO-8601, igual a DateTime.weekday).
--
-- `category` é texto livre e alimenta a cor da célula na grade: o
-- AppColors.accentFor() do app deriva o acento do vitral a partir desta
-- string. Reutilize as mesmas categorias para manter as cores consistentes —
-- uma categoria nova ganha automaticamente uma das 5 cores.
--
-- weekly_slots não tem chave natural (a base pode ter dois compromissos no
-- mesmo horário), então a idempotência vem de um guard explícito em vez de
-- `on conflict`, que nunca dispararia.
with modelo (weekday, starts_at, ends_at, title, location, category) as (

  -- Itens de segunda a sexta: o cross join evita repetir 5 vezes cada linha.
  select d.weekday, t.starts_at, t.ends_at, t.title, t.location, t.category
    from (values (1), (2), (3), (4), (5)) as d(weekday)
   cross join (values
     ('06:30'::time, '07:30'::time, 'Intercessão',   'Sala de oração', 'oracao'),
     ('07:30'::time, '08:30'::time, 'Café da manhã', 'Cozinha',        'refeicao'),
     ('08:30'::time, '09:00'::time, 'Devocional',    'Salão',          'comunhao'),
     ('12:00'::time, '13:00'::time, 'Almoço',        'Cozinha',        'refeicao'),
     ('18:30'::time, '19:30'::time, 'Jantar',        'Cozinha',        'refeicao')
   ) as t(starts_at, ends_at, title, location, category)

  union all

  -- Itens de dias específicos.
  select * from (values
    -- Manhãs: serviço na base alternando com ensino.
    (1, '09:00'::time, '12:00'::time, 'Servir ao Todo',      'Base',           'servico'),
    (3, '09:00'::time, '12:00'::time, 'Servir ao Todo',      'Base',           'servico'),
    (5, '09:00'::time, '12:00'::time, 'Servir ao Todo',      'Base',           'servico'),
    (2, '09:00'::time, '12:00'::time, 'Aulas e discipulado', 'Salão',          'ensino'),
    (4, '09:00'::time, '12:00'::time, 'Aulas e discipulado', 'Salão',          'ensino'),

    -- Tardes.
    (2, '14:00'::time, '17:00'::time, 'Evangelismo',         'Externo',        'evangelismo'),
    (4, '14:00'::time, '17:00'::time, 'Evangelismo',         'Externo',        'evangelismo'),
    (1, '14:00'::time, '17:00'::time, 'Trabalho e projetos', 'Base',           'servico'),
    (3, '14:00'::time, '17:00'::time, 'Trabalho e projetos', 'Base',           'servico'),
    (5, '14:00'::time, '16:00'::time, 'Reunião de equipe',   'Salão',          'comunhao'),

    -- Noites.
    (3, '19:30'::time, '21:00'::time, 'Culto de oração',     'Salão',          'oracao'),

    -- Fim de semana: ritmo mais leve.
    (6, '08:00'::time, '09:00'::time, 'Café da manhã',       'Cozinha',        'refeicao'),
    (6, '09:00'::time, '12:00'::time, 'Ação social',         'Externo',        'evangelismo'),
    (7, '09:00'::time, '10:00'::time, 'Café da manhã',       'Cozinha',        'refeicao'),
    (7, '19:00'::time, '21:00'::time, 'Culto',               'Salão',          'comunhao')
  ) as e(weekday, starts_at, ends_at, title, location, category)
)
insert into public.weekly_slots
  (weekday, starts_at, ends_at, title, location, category)
select m.weekday::smallint, m.starts_at, m.ends_at, m.title, m.location, m.category
  from modelo m
 where not exists (
   select 1 from public.weekly_slots w
    where w.weekday = m.weekday::smallint
      and w.starts_at = m.starts_at
      and w.title = m.title
 );

-- ---- Convite inicial ----
-- max_uses 20 = um por obreiro da base. O índice único é em upper(code).
insert into public.invites (code, role, max_uses, note)
values ('VEREDAS2026', 'obreiro', 20, 'Convite inicial dos obreiros')
on conflict do nothing;
