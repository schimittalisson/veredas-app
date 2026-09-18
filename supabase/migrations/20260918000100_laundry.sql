-- =========================================================================
-- Lavanderia — reserva de máquina de lavar pelos próprios obreiros
--
-- Substitui a planilha semanal que a base mantinha à mão: linhas são faixas
-- de horário, colunas são as máquinas, e cada célula é "livre", "intervalo"
-- (máquina indisponível) ou "reservado por fulano".
--
-- -------------------------------------------------------------------------
-- Quatro tabelas, e por quê
-- -------------------------------------------------------------------------
--
--   laundry_machines    as máquinas (cadastráveis: a base tem 3 hoje)
--   laundry_time_slots  as faixas de horário da grade (05:30, 07:30, …)
--   laundry_blocks      bloqueios RECORRENTES por dia da semana
--   laundry_reservations as reservas, sempre numa DATA concreta
--
-- Máquinas e horários são cadastro, e não constante no código, porque mudar
-- um horário não pode exigir publicar versão nova nas lojas.
--
-- O bloqueio é (máquina, dia da semana, faixa) e vale para toda semana: é o
-- que a planilha da base mostra — o padrão de intervalos se repete. Bloqueio
-- por data avulsa ficou de fora de propósito; se um dia for preciso, entra
-- como uma coluna `on_date` nullable nesta mesma tabela.
--
-- A reserva é (máquina, faixa, data): ela acontece num dia específico, e é o
-- que permite o histórico e a navegação por semana.
--
-- -------------------------------------------------------------------------
-- A corrida entre duas pessoas reservando o mesmo horário
-- -------------------------------------------------------------------------
--
-- É o ponto crítico desta feature. A garantia NÃO é a checagem no app, que
-- olha um cache possivelmente velho — é o índice único parcial
-- `laundry_reservations_unique_idx`. A segunda gravação simplesmente não
-- entra, e o erro 23505 vira `AppErrorCode.conflict` no app, que mostra
-- "horário já reservado, atualize para ver os horários atualizados".
--
-- O índice é PARCIAL (`where deleted_at is null`) porque cancelar é soft
-- delete: sem isso, um horário cancelado ficaria travado para sempre.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Tabelas
-- -------------------------------------------------------------------------

create table public.laundry_machines (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  -- "grande", "pequena", "não usar" — o que a planilha trazia no cabeçalho.
  note       text,
  is_active  boolean not null default true,
  ordering   integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index laundry_machines_order_idx on public.laundry_machines (ordering)
  where deleted_at is null;
create index laundry_machines_updated_at_idx on public.laundry_machines (updated_at);

create table public.laundry_time_slots (
  id         uuid primary key default gen_random_uuid(),
  starts_at  time not null,
  ends_at    time,
  is_active  boolean not null default true,
  ordering   integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint laundry_time_slots_times_ordered
    check (ends_at is null or ends_at > starts_at)
);

create index laundry_time_slots_order_idx
  on public.laundry_time_slots (ordering, starts_at) where deleted_at is null;
create index laundry_time_slots_updated_at_idx
  on public.laundry_time_slots (updated_at);

create table public.laundry_blocks (
  id           uuid primary key default gen_random_uuid(),
  machine_id   uuid not null references public.laundry_machines(id) on delete cascade,
  time_slot_id uuid not null references public.laundry_time_slots(id) on delete cascade,
  -- ISO-8601, igual ao `weekly_slots.weekday` e ao `DateTime.weekday` do Dart.
  weekday      smallint not null check (weekday between 1 and 7),
  reason       text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

-- Bloquear duas vezes a mesma célula não significa nada; o índice evita a
-- linha duplicada que faria a tela desenhar "intervalo" em cima de "intervalo".
create unique index laundry_blocks_unique_idx
  on public.laundry_blocks (machine_id, time_slot_id, weekday)
  where deleted_at is null;
create index laundry_blocks_updated_at_idx on public.laundry_blocks (updated_at);

create table public.laundry_reservations (
  id           uuid primary key default gen_random_uuid(),
  machine_id   uuid not null references public.laundry_machines(id) on delete cascade,
  time_slot_id uuid not null references public.laundry_time_slots(id) on delete cascade,
  on_date      date not null,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

-- A garantia real contra reserva dupla. Ver o cabeçalho.
create unique index laundry_reservations_unique_idx
  on public.laundry_reservations (machine_id, time_slot_id, on_date)
  where deleted_at is null;

create index laundry_reservations_grid_idx
  on public.laundry_reservations (on_date) where deleted_at is null;
create index laundry_reservations_updated_at_idx
  on public.laundry_reservations (updated_at);

-- -------------------------------------------------------------------------
-- 2. updated_at automático
-- -------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array[
    'laundry_machines','laundry_time_slots','laundry_blocks','laundry_reservations'
  ] loop
    execute format(
      'create trigger %I_touch_updated_at before update on public.%I
         for each row execute function public.touch_updated_at()', t, t);
  end loop;
end;
$$;

-- -------------------------------------------------------------------------
-- 3. RLS
--
-- Leitura: qualquer aprovado — a grade é compartilhada, todo mundo precisa
-- ver quem reservou o quê.
--
-- Cadastro (máquinas, horários, bloqueios): só admin.
--
-- Reservas: NÃO há policy de insert/update/delete direto. Reservar e cancelar
-- passam pelas RPCs abaixo, que são `security definer`. Deixar o insert
-- aberto permitiria reservar em nome de outra pessoa e ignorar os bloqueios,
-- já que policy não consegue expressar "e a célula não pode estar bloqueada".
-- -------------------------------------------------------------------------

alter table public.laundry_machines     enable row level security;
alter table public.laundry_time_slots   enable row level security;
alter table public.laundry_blocks       enable row level security;
alter table public.laundry_reservations enable row level security;

create policy laundry_machines_select on public.laundry_machines
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy laundry_machines_admin_write on public.laundry_machines
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy laundry_time_slots_select on public.laundry_time_slots
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy laundry_time_slots_admin_write on public.laundry_time_slots
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy laundry_blocks_select on public.laundry_blocks
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy laundry_blocks_admin_write on public.laundry_blocks
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Repare que esta policy NÃO filtra `deleted_at is null`, ao contrário das
-- outras do projeto. É deliberado, e a diferença importa.
--
-- O pull incremental só aprende que uma linha morreu quando ela volta do
-- servidor COM `deleted_at` preenchido (ver `sync_service.dart`). Se a policy
-- escondesse as canceladas, o app jamais saberia do cancelamento e a reserva
-- ficaria eternamente na grade dos outros aparelhos — o horário nunca mais
-- seria reservável.
--
-- Não há custo de privacidade: a linha cancelada não diz nada que a linha viva
-- já não dissesse, e quem enxerga a grade enxerga todas as reservas.
--
-- As outras três tabelas da lavanderia mantêm o filtro porque são
-- sincronizadas por substituição total, que reconcilia pela ausência.
create policy laundry_reservations_select on public.laundry_reservations
  for select to authenticated using (public.is_approved());

-- -------------------------------------------------------------------------
-- 4. RPCs de reserva
-- -------------------------------------------------------------------------

-- 4.1 reserve_laundry_slot — reserva uma célula da grade para quem chamou.
--
-- Devolve o id da reserva criada. Erros possíveis, todos traduzidos no app:
--   LAUNDRY_SLOT_BLOCKED  a célula é intervalo naquele dia da semana
--   LAUNDRY_PAST_DATE     a data já passou
--   23505 (unique)        alguém reservou primeiro
create or replace function public.reserve_laundry_slot(
  p_machine_id   uuid,
  p_time_slot_id uuid,
  p_on_date      date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if not public.is_approved() then
    raise exception 'FORBIDDEN_NOT_APPROVED';
  end if;

  -- Reservar no passado não tem utilidade e bagunçaria o histórico.
  if p_on_date < (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'LAUNDRY_PAST_DATE';
  end if;

  -- A máquina e a faixa precisam existir e estar ativas: um cadastro
  -- desativado some da grade, e reservar nele deixaria uma reserva órfã que
  -- ninguém veria para cancelar.
  if not exists (
    select 1 from public.laundry_machines
     where id = p_machine_id and is_active and deleted_at is null
  ) then
    raise exception 'LAUNDRY_MACHINE_NOT_FOUND';
  end if;

  if not exists (
    select 1 from public.laundry_time_slots
     where id = p_time_slot_id and is_active and deleted_at is null
  ) then
    raise exception 'LAUNDRY_TIME_SLOT_NOT_FOUND';
  end if;

  -- O bloqueio é por dia da semana. `extract(isodow)` devolve 1..7 com
  -- segunda = 1, exatamente a convenção usada na coluna `weekday`.
  if exists (
    select 1 from public.laundry_blocks
     where machine_id = p_machine_id
       and time_slot_id = p_time_slot_id
       and weekday = extract(isodow from p_on_date)
       and deleted_at is null
  ) then
    raise exception 'LAUNDRY_SLOT_BLOCKED';
  end if;

  -- Sem checagem de "já existe reserva" aqui de propósito: entre o select e o
  -- insert cabe outra transação. Quem garante é o índice único, e o 23505 que
  -- ele levanta é tratado no app como "horário já reservado".
  insert into public.laundry_reservations (machine_id, time_slot_id, on_date, user_id)
  values (p_machine_id, p_time_slot_id, p_on_date, v_uid)
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.reserve_laundry_slot(uuid, uuid, date) from public, anon;
grant execute on function public.reserve_laundry_slot(uuid, uuid, date) to authenticated;

-- 4.2 cancel_laundry_reservation — cancela a própria reserva (ou qualquer
-- uma, se for admin).
--
-- Soft delete, e não `delete`: o pull incremental do app só descobre que uma
-- linha morreu quando ela volta com `deleted_at` preenchido. Um delete físico
-- deixaria a reserva cancelada visível para sempre nos aparelhos.
create or replace function public.cancel_laundry_reservation(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select user_id into v_owner
    from public.laundry_reservations
   where id = p_id and deleted_at is null;

  if not found then
    raise exception 'LAUNDRY_RESERVATION_NOT_FOUND';
  end if;

  if v_owner <> v_uid and not public.is_admin() then
    raise exception 'FORBIDDEN_NOT_OWNER';
  end if;

  update public.laundry_reservations
     set deleted_at = now(), updated_at = now()
   where id = p_id;
end;
$$;

revoke all on function public.cancel_laundry_reservation(uuid) from public, anon;
grant execute on function public.cancel_laundry_reservation(uuid) to authenticated;

-- -------------------------------------------------------------------------
-- 5. View da grade
--
-- A tela precisa do NOME de quem reservou, e `profiles` já é legível por
-- qualquer aprovado — mas fazer o app cruzar as duas tabelas no cache exigiria
-- que o perfil de quem reservou estivesse sincronizado, o que nem sempre é
-- verdade logo após alguém entrar na base. A view resolve no servidor.
--
-- Igual a `prayer_feed`: é somente leitura, e as escritas vão pelas RPCs.
-- -------------------------------------------------------------------------

create or replace view public.laundry_grid
with (security_invoker = true)
as
select
  r.id,
  r.machine_id,
  r.time_slot_id,
  r.on_date,
  r.user_id,
  p.full_name as user_name,
  r.created_at,
  r.updated_at,
  r.deleted_at
from public.laundry_reservations r
join public.profiles p on p.id = r.user_id;

grant select on public.laundry_grid to authenticated;
