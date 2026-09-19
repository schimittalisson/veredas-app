-- =========================================================================
-- Seed da lavanderia — as máquinas e os horários da planilha da base
--
-- Rode UMA VEZ no SQL Editor, depois de aplicar
-- `migrations/20260918000100_laundry.sql`.
--
-- Cadastra as 3 máquinas, as 10 faixas de horário e os bloqueios que a
-- planilha mostra.
--
-- É idempotente: rodar de novo não duplica nada.
-- =========================================================================

-- As máquinas, na ordem em que aparecem nas colunas da planilha.
insert into public.laundry_machines (name, note, ordering)
select * from (values
  ('Máquina 1', 'grande',  1),
  ('Máquina 2', 'pequena', 2),
  ('Máquina 3', null,      3)
) as v(name, note, ordering)
where not exists (
  select 1 from public.laundry_machines m
   where m.name = v.name and m.deleted_at is null
);

-- As faixas de horário, na ordem das linhas da planilha.
insert into public.laundry_time_slots (starts_at, ordering)
select * from (values
  ('05:30'::time,  1),
  ('07:30'::time,  2),
  ('09:00'::time,  3),
  ('11:00'::time,  4),
  ('12:30'::time,  5),
  ('14:30'::time,  6),
  ('16:00'::time,  7),
  ('18:30'::time,  8),
  ('20:00'::time,  9),
  ('22:00'::time, 10)
) as v(starts_at, ordering)
where not exists (
  select 1 from public.laundry_time_slots s
   where s.starts_at = v.starts_at and s.deleted_at is null
);

-- -------------------------------------------------------------------------
-- Bloqueios ("Intervalo" e "Encerra" da planilha)
-- -------------------------------------------------------------------------
--
-- A planilha distingue **Intervalo** (pausa entre lavagens) de **Encerra**
-- (lavanderia fechada). Aqui os dois viram bloqueio, que é o único conceito
-- que o app tem hoje: em ambos os casos a máquina não pode ser usada, e é isso
-- que importa para impedir a reserva. A coluna `reason` fica nula; quando
-- alguém quiser separar os dois rótulos, é nela que a distinção entra.
--
-- Leitura da planilha, célula a célula:
--
--   07:30, 11:00, 14:30  bloqueados em TODOS os dias e máquinas
--   18:30                bloqueado em todos (segunda e domingo como
--                        "Intervalo"; de terça a sábado como "Encerra")
--   22:00                bloqueado só na segunda e no domingo
--   05:30, 09:00, 12:30, 16:00, 20:00   livres
--
-- Células vazias da planilha ficaram livres, sem inferência. Se de terça a
-- sábado a lavanderia fecha às 18:30, os horários de 20:00 e 22:00 desses dias
-- provavelmente também deveriam estar bloqueados — mas a planilha os deixa em
-- branco, e adivinhar aqui seria pior do que marcar dois toques no app.
--
-- Weekday é ISO: 1 = segunda … 7 = domingo.
insert into public.laundry_blocks (machine_id, time_slot_id, weekday)
select m.id, s.id, d.weekday
  from public.laundry_machines m
 cross join public.laundry_time_slots s
 cross join (values (1),(2),(3),(4),(5),(6),(7)) as d(weekday)
 where m.deleted_at is null
   and s.deleted_at is null
   and (
        s.starts_at in ('07:30'::time, '11:00'::time, '14:30'::time, '18:30'::time)
     or (s.starts_at = '22:00'::time and d.weekday in (1, 7))
   )
   and not exists (
     select 1 from public.laundry_blocks b
      where b.machine_id = m.id
        and b.time_slot_id = s.id
        and b.weekday = d.weekday
        and b.deleted_at is null
   );

-- Confirmação rápida: esperado 3 máquinas, 10 horários e 90 bloqueios
-- (4 faixas × 7 dias × 3 máquinas = 84, mais 22:00 em 2 dias × 3 máquinas = 6).
select
  (select count(*) from public.laundry_machines   where deleted_at is null) as maquinas,
  (select count(*) from public.laundry_time_slots where deleted_at is null) as horarios,
  (select count(*) from public.laundry_blocks     where deleted_at is null) as bloqueios;
