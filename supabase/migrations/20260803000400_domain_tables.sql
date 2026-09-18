-- =========================================================================
-- §4 — Tabelas de domínio
--
-- Convenção obrigatória em toda tabela sincronizada (ver docs/PLANO.md §2.5):
--   updated_at timestamptz  -> marca d'água do pull incremental (trigger na 0800)
--   deleted_at timestamptz  -> soft delete; sem isso um dispositivo offline
--                              nunca descobre que uma linha foi removida.
--
-- Exceções conscientes: scale_managers e prayer_interactions não têm
-- deleted_at. Elas sofrem DELETE físico e têm estratégia de sync própria
-- (full replace / não cacheada). Ver docs/SCHEMA.md "Estratégia de sync por tabela".
-- =========================================================================

-- -------------------------------------------------------------------------
-- 4.1 Escalas
-- -------------------------------------------------------------------------

-- Tipos de escala são DADOS, não código. Adicionar uma escala nova é um
-- INSERT — não exige release do app (a TabBar é gerada a partir daqui).
create table public.scale_types (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,
  name        text not null,
  description text,
  icon        text,                          -- nome do Material Icon
  cadence     text not null default 'weekly'
                check (cadence in ('weekly', 'monthly', 'adhoc')),
  slots       text[] not null default '{}',  -- turnos/áreas sugeridos
  ordering    integer not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- Quem pode editar cada escala. Esta tabela É o requisito de permissão
-- central do app: "só o responsável pela escala X pode editá-la".
create table public.scale_managers (
  scale_type_id uuid not null references public.scale_types(id) on delete cascade,
  user_id       uuid not null references public.profiles(id)   on delete cascade,
  assigned_by   uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (scale_type_id, user_id)
);

create index scale_managers_user_idx on public.scale_managers (user_id);

-- Uma atribuição = uma pessoa responsável por uma tarefa/turno em uma data.
-- Modelo deliberadamente genérico para servir aos 5 tipos de escala:
--   Servir ao Todo   -> task = área ("Cozinha", "Banheiros")
--   Lixo             -> sem task, um responsável por dia/semana
--   Café da Manhã    -> slot = turno, task opcional
--   Intercessão     -> slot = horário ("06:00-07:00")
--   Café da Gratidão -> evento pontual, cadence 'adhoc'
create table public.scale_assignments (
  id            uuid primary key default gen_random_uuid(),
  scale_type_id uuid not null references public.scale_types(id) on delete cascade,
  starts_on     date not null,
  ends_on       date,
  slot          text,
  task          text,
  assignee_id   uuid references public.profiles(id) on delete set null,
  assignee_name text,          -- para quem não tem conta no app
  notes         text,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  constraint assignment_has_assignee
    check (assignee_id is not null or nullif(trim(assignee_name), '') is not null),
  constraint assignment_dates_ordered
    check (ends_on is null or ends_on >= starts_on)
);

create index scale_assignments_lookup_idx
  on public.scale_assignments (scale_type_id, starts_on)
  where deleted_at is null;
create index scale_assignments_assignee_idx
  on public.scale_assignments (assignee_id) where deleted_at is null;
create index scale_assignments_updated_at_idx
  on public.scale_assignments (updated_at);

-- -------------------------------------------------------------------------
-- 4.2 Agenda
-- -------------------------------------------------------------------------

-- Eventos pontuais. starts_at/ends_at são timestamptz: guardamos em UTC e
-- exibimos no fuso local do dispositivo, o que trata horário de verão de graça.
create table public.events (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  description     text,
  starts_at       timestamptz not null,
  ends_at         timestamptz,
  all_day         boolean not null default false,
  location        text,
  category        text,
  cover_image_url text,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  constraint events_dates_ordered check (ends_at is null or ends_at >= starts_at)
);

create index events_starts_at_idx on public.events (starts_at) where deleted_at is null;
create index events_updated_at_idx on public.events (updated_at);

-- Cronograma semanal fixo (a "planilha"). Repete toda semana.
-- weekday segue ISO-8601: 1 = segunda ... 7 = domingo, igual a
-- DateTime.weekday do Dart — evita conversão no cliente.
create table public.weekly_slots (
  id         uuid primary key default gen_random_uuid(),
  weekday    smallint not null check (weekday between 1 and 7),
  starts_at  time not null,
  ends_at    time,
  title      text not null,
  location   text,
  category   text,
  notes      text,
  is_active  boolean not null default true,
  ordering   integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint weekly_slots_times_ordered check (ends_at is null or ends_at > starts_at)
);

create index weekly_slots_grid_idx on public.weekly_slots (weekday, starts_at)
  where deleted_at is null;
create index weekly_slots_updated_at_idx on public.weekly_slots (updated_at);

-- -------------------------------------------------------------------------
-- 4.3 Mural de oração
-- -------------------------------------------------------------------------
create table public.prayer_posts (
  id           uuid primary key default gen_random_uuid(),
  author_id    uuid not null references public.profiles(id) on delete cascade,
  title        text not null check (length(trim(title)) between 3 and 120),
  body         text not null check (length(trim(body)) between 1 and 4000),
  is_anonymous boolean not null default false,
  answered_at  timestamptz,
  answer_note  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

create index prayer_posts_created_at_idx on public.prayer_posts (created_at desc)
  where deleted_at is null;
create index prayer_posts_author_idx on public.prayer_posts (author_id)
  where deleted_at is null;
create index prayer_posts_updated_at_idx on public.prayer_posts (updated_at);

-- Índice trigram sobre o título normalizado: é o que faz a busca por título
-- ("cura" acha "Curá") não virar full scan.
create index prayer_posts_title_trgm_idx
  on public.prayer_posts using gin (public.norm_text(title) extensions.gin_trgm_ops);

-- Idem para o corpo: search_prayers também procura no body, e sem este índice
-- a segunda metade do OR faria scan sequencial.
create index prayer_posts_body_trgm_idx
  on public.prayer_posts using gin (public.norm_text(body) extensions.gin_trgm_ops);

-- "Estou orando por isso". PK composta impede contagem dupla no duplo toque.
create table public.prayer_interactions (
  post_id    uuid not null references public.prayer_posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.prayer_comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.prayer_posts(id) on delete cascade,
  author_id  uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index prayer_comments_post_idx on public.prayer_comments (post_id, created_at)
  where deleted_at is null;
create index prayer_comments_updated_at_idx on public.prayer_comments (updated_at);

-- -------------------------------------------------------------------------
-- 4.4 Início / institucional
-- -------------------------------------------------------------------------

-- Avisos da liderança (o cartão do topo da tela Início).
create table public.announcements (
  id         uuid primary key default gen_random_uuid(),
  author_id  uuid references public.profiles(id) on delete set null,
  title      text,
  body       text not null,
  pinned     boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index announcements_feed_idx
  on public.announcements (pinned desc, created_at desc) where deleted_at is null;
create index announcements_updated_at_idx on public.announcements (updated_at);

-- "Dados da Base": chave/valor ordenado, exibido como acordeão.
-- Formato chave/valor (em vez de colunas fixas) permite ao admin adicionar
-- um item novo sem alterar o schema nem o app.
create table public.base_info (
  id         uuid primary key default gen_random_uuid(),
  key        text not null unique,
  label      text not null,
  value      text not null,
  ordering   integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.social_links (
  id         uuid primary key default gen_random_uuid(),
  platform   text not null check (platform in
               ('instagram','facebook','x','youtube','tiktok','whatsapp','site')),
  url        text not null,
  label      text,
  ordering   integer not null default 0,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Uma rede social por plataforma. Sem isto, o `on conflict do nothing` do
-- seed.sql nunca dispara e reaplicar o seed duplicaria os ícones da tela Início.
create unique index social_links_platform_key on public.social_links (platform);
