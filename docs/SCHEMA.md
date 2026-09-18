# Veredas App — Schema do Supabase

SQL completo do backend. **Aplique os blocos na ordem em que aparecem** — há
dependências entre eles (tipos → funções → tabelas → policies → triggers →
seeds).

Salve cada seção como uma migration em `supabase/migrations/`, com prefixo
ordenável:

```
supabase/migrations/
  20260803000100_extensions_and_types.sql   # §1
  20260803000200_profiles_and_invites.sql   # §2
  20260803000300_helper_functions.sql       # §3
  20260803000400_domain_tables.sql          # §4
  20260803000500_views_and_rpcs.sql         # §5
  20260803000600_rls_policies.sql           # §6
  20260803000700_storage.sql                # §7
  20260803000800_triggers.sql               # §8
supabase/seed.sql                           # §9
```

## Convenções aplicadas a todas as tabelas de domínio

Estas duas colunas são **obrigatórias** e não negociáveis — a sincronização
offline depende delas (ver `PLANO.md` §2.5):

- `updated_at timestamptz not null default now()` — mantida por trigger (§8),
  usada como marca d'água do *pull* incremental.
- `deleted_at timestamptz` — **soft delete**. O cliente nunca faz `DELETE`
  físico; marca `deleted_at`. Sem isso, um dispositivo offline nunca descobre
  que uma linha foi removida.

Toda leitura no app filtra `deleted_at is null`.

### Estratégia de sincronização por tabela

Duas tabelas **não** têm `deleted_at`, por decisão consciente. Elas não podem
usar *pull* incremental, porque uma remoção seria invisível para um cliente
offline. Cada uma tem uma estratégia própria:

| Tabela | Estratégia de sync | Por quê |
|---|---|---|
| `invites`, `scale_types`, `scale_assignments`, `events`, `weekly_slots`, `prayer_posts`, `prayer_comments`, `announcements`, `base_info`, `social_links` | **Incremental** por `updated_at` + *soft delete* | Volume pode crescer; incremental é eficiente |
| `profiles` | **Substituição total** a cada sync | Tem `deleted_at`, mas o soft delete não é o único caminho: apagar a conta em `auth.users` (pelo painel, ou um `delete` direto no banco) leva o perfil junto em cascata, sem deixar *tombstone*. O incremental nunca descobria, e a tela de Membros listava contas que não existiam mais. Base pequena — dezenas de obreiros —, então baixar tudo é barato |
| `scale_managers` | **Substituição total** (`delete from` local + insert de tudo) a cada sync | Máximo ~50 linhas. Remover um responsável é um `DELETE` físico, que o incremental não detectaria. Full replace é trivial e sempre correto |
| `prayer_interactions` | **Não é cacheada.** Os contadores e o `is_praying` vêm da view `prayer_feed`; o cache local guarda o resultado da view | "Desmarcar estou orando" é um `DELETE` físico. Cachear a tabela crua exigiria *tombstones* sem ganho algum |

Consequência prática para a Fase 4: `sync_entity.dart` precisa de um campo
`SyncMode { incremental, fullReplace }` e a tabela local do mural espelha a
**view** `prayer_feed`, não `prayer_posts`. Escritas otimistas de "estou orando"
ajustam `praying_count`/`is_praying` na linha cacheada da view.

---

## §1 — Extensões e tipos

> **Atenção ao schema das extensões.** No Supabase, extensões instaladas pelo
> painel vão para o schema `extensions`; um `create extension` avulso pode cair
> em `public`. Os blocos abaixo qualificam como `extensions.unaccent` e
> `extensions.gin_trgm_ops`. **Confirme onde ficaram** antes de aplicar o §3 e o
> §4.3:
>
> ```sql
> select e.extname, n.nspname as schema
>   from pg_extension e join pg_namespace n on n.oid = e.extnamespace
>  where e.extname in ('pg_trgm', 'unaccent');
> ```
>
> Se o resultado for `public`, remova o prefixo `extensions.` das referências
> (ou rode `alter extension unaccent set schema extensions;`). Um prefixo errado
> aqui gera `function ... does not exist` na criação do índice.

```sql
create extension if not exists pg_trgm  with schema extensions;
create extension if not exists unaccent with schema extensions;

-- Papéis globais. "Responsável por escala" NÃO é um papel global: é uma
-- atribuição por tipo de escala, na tabela scale_managers (§4).
create type public.app_role as enum ('admin', 'obreiro');
```

---

## §2 — Perfis e convites

```sql
-- ---------------------------------------------------------------------------
-- profiles: espelho de auth.users com os dados de domínio.
-- Nunca escrever em auth.users diretamente.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  full_name    text not null,
  email        text,
  phone        text,
  avatar_url   text,
  bio          text,
  role         public.app_role not null default 'obreiro',
  is_approved  boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

create index profiles_role_idx on public.profiles (role) where deleted_at is null;
create index profiles_updated_at_idx on public.profiles (updated_at);

-- ---------------------------------------------------------------------------
-- Cria o profile automaticamente quando um usuário se registra no Auth.
-- security definer: o trigger roda com privilégios do owner, ignorando RLS.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      split_part(new.email, '@', 1)
    ),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- invites: cadastro só acontece com um código válido.
-- ---------------------------------------------------------------------------
create table public.invites (
  id          uuid primary key default gen_random_uuid(),
  code        text not null,
  role        public.app_role not null default 'obreiro',
  note        text,
  max_uses    integer not null default 1 check (max_uses > 0),
  uses        integer not null default 0,
  expires_at  timestamptz,
  revoked_at  timestamptz,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- Comparação de código é case-insensitive: o índice único também precisa ser.
create unique index invites_code_key on public.invites (upper(code));
```

---

## §3 — Funções auxiliares de permissão

**Ponto de atenção crítico.** Uma policy em `profiles` que faça
`select ... from profiles` causa **recursão infinita** de RLS (erro
`infinite recursion detected in policy`). A solução é encapsular a consulta em
funções `security definer`, que rodam com privilégios do owner e portanto não
reavaliam RLS.

```sql
-- Está aprovado? (base de toda leitura)
create or replace function public.is_approved()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.is_approved from public.profiles p
      where p.id = auth.uid() and p.deleted_at is null),
    false
  );
$$;

-- É admin? (implica aprovado)
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select p.is_approved and p.role = 'admin' from public.profiles p
      where p.id = auth.uid() and p.deleted_at is null),
    false
  );
$$;

-- Gerencia este tipo de escala? Admin gerencia todos.
create or replace function public.manages_scale(p_scale_type_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or exists (
    select 1 from public.scale_managers m
     where m.scale_type_id = p_scale_type_id
       and m.user_id = auth.uid()
  );
$$;

-- Normalização para busca: minúsculas sem acento.
-- immutable + strict permite uso em índice de expressão.
create or replace function public.norm_text(p text)
returns text
language sql
immutable
strict
parallel safe
as $$
  select lower(extensions.unaccent('extensions.unaccent', p));
$$;

revoke all on function public.is_approved() from public;
revoke all on function public.is_admin() from public;
revoke all on function public.manages_scale(uuid) from public;
grant execute on function public.is_approved()        to authenticated;
grant execute on function public.is_admin()           to authenticated;
grant execute on function public.manages_scale(uuid)  to authenticated;
grant execute on function public.norm_text(text)      to authenticated;
```

> `manages_scale` referencia `scale_managers`, criada em §4. Em Postgres, o corpo
> de uma função `language sql` só é resolvido na execução, então criar a função
> antes da tabela funciona. Se seu ambiente reclamar
> (`check_function_bodies = on`), mova este bloco para depois do §4.

---

## §4 — Tabelas de domínio

### 4.1 Escalas

```sql
-- Tipos de escala são DADOS, não código. Adicionar uma escala nova é um
-- INSERT — não exige release do app (a TabBar é gerada a partir daqui).
create table public.scale_types (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,
  name        text not null,
  description text,
  icon        text,                       -- nome do Material Icon
  cadence     text not null default 'weekly'
                check (cadence in ('weekly', 'monthly', 'adhoc')),
  slots       text[] not null default '{}',  -- turnos/áreas sugeridos
  ordering    integer not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- Quem pode editar cada escala. Esta tabela É o requisito de permissão.
create table public.scale_managers (
  scale_type_id uuid not null references public.scale_types(id) on delete cascade,
  user_id       uuid not null references public.profiles(id)   on delete cascade,
  assigned_by   uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  primary key (scale_type_id, user_id)
);

create index scale_managers_user_idx on public.scale_managers (user_id);

-- Uma atribuição = uma EQUIPE responsável por uma tarefa/turno em uma data,
-- com um responsável geral opcional sobre ela.
-- Modelo deliberadamente genérico para servir aos 6 tipos de escala:
--   Servir ao Todo   -> task = área ("Cozinha", "Banheiros")
--   Lixo             -> sem task, um responsável por dia/semana
--   Café da Manhã    -> slot = turno, task opcional
--   Almoço           -> sem slot, a equipe do dia (+ responsável geral)
--   Intercessão     -> slot = horário ("06:00-07:00")
--   Café da Gratidão -> evento pontual, cadence 'adhoc'
--
-- A equipe é um par de arrays na própria linha, e não uma tabela filha: uma
-- edição offline de quatro pessoas precisa ser UMA entrada na outbox, senão o
-- rollback do cache otimista viraria transação distribuída no cliente. O preço
-- é não ter FK por elemento (o Postgres não faz) — quem tira o uid das equipes
-- ao apagar a conta é `delete_own_account()`.
create table public.scale_assignments (
  id            uuid primary key default gen_random_uuid(),
  scale_type_id uuid not null references public.scale_types(id) on delete cascade,
  starts_on     date not null,
  ends_on       date,
  slot          text,
  task          text,

  -- Responsável GERAL (opcional), não "a pessoa escalada" — a equipe está
  -- logo abaixo. Os nomes das colunas ficaram por compatibilidade: o app
  -- anterior às equipes lê `assignee_name` para desenhar a escala, e renomear
  -- derrubaria esses aparelhos até todo mundo atualizar.
  assignee_id   uuid references public.profiles(id) on delete set null,
  assignee_name text,

  member_ids    uuid[] not null default '{}',   -- equipe, quem tem conta
  member_names  text[] not null default '{}',   -- equipe, quem não tem conta

  notes         text,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  constraint assignment_has_someone
    check (
      assignee_id is not null
      or nullif(trim(assignee_name), '') is not null
      or cardinality(member_ids) > 0
      or cardinality(member_names) > 0
    ),
  constraint assignment_dates_ordered
    check (ends_on is null or ends_on >= starts_on)
);

create index scale_assignments_lookup_idx
  on public.scale_assignments (scale_type_id, starts_on)
  where deleted_at is null;
create index scale_assignments_assignee_idx
  on public.scale_assignments (assignee_id) where deleted_at is null;
-- GIN porque a pergunta "em quais escalas eu estou?" vira `member_ids @> ...`,
-- e contenção de array não usa btree.
create index scale_assignments_members_idx
  on public.scale_assignments using gin (member_ids);
create index scale_assignments_updated_at_idx
  on public.scale_assignments (updated_at);
```

> As colunas de equipe e o CHECK `assignment_has_someone` chegaram na migration
> `20260917000100_scale_teams_and_lunch.sql`, que também acrescentou a escala
> de Almoço. O CHECK anterior chamava-se `assignment_has_assignee`.

### 4.2 Agenda

```sql
-- Eventos pontuais.
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
-- weekday segue ISO-8601: 1 = segunda ... 7 = domingo (igual a DateTime.weekday
-- do Dart, evitando conversão).
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
```

### 4.3 Mural de oração

```sql
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

-- Índice trigram sobre o título normalizado: acelera a busca por título.
create index prayer_posts_title_trgm_idx
  on public.prayer_posts using gin (public.norm_text(title) extensions.gin_trgm_ops);

-- "Estou orando por isso". PK composta impede contagem dupla.
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
```

### 4.4 Início / institucional

```sql
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
```

---

## §5 — Views e RPCs

```sql
-- ---------------------------------------------------------------------------
-- Feed de oração com contadores agregados. security_invoker = true faz a view
-- respeitar o RLS de quem consulta (Postgres 15+, padrão no Supabase).
-- Sem isso, a view rodaria como owner e vazaria dados.
-- ---------------------------------------------------------------------------
create or replace view public.prayer_feed
with (security_invoker = true) as
select
  p.id,
  p.author_id,
  p.title,
  p.body,
  p.is_anonymous,
  p.answered_at,
  p.answer_note,
  p.created_at,
  p.updated_at,
  case when p.is_anonymous then null else a.full_name  end as author_name,
  case when p.is_anonymous then null else a.avatar_url end as author_avatar_url,
  (select count(*) from public.prayer_interactions i where i.post_id = p.id)
    as praying_count,
  (select count(*) from public.prayer_comments c
     where c.post_id = p.id and c.deleted_at is null) as comment_count,
  exists (select 1 from public.prayer_interactions i
            where i.post_id = p.id and i.user_id = auth.uid()) as is_praying
from public.prayer_posts p
join public.profiles a on a.id = p.author_id
where p.deleted_at is null;

grant select on public.prayer_feed to authenticated;

-- ---------------------------------------------------------------------------
-- Busca por título, ignorando acento e caixa.
-- ---------------------------------------------------------------------------
create or replace function public.search_prayers(
  p_term text,
  p_limit integer default 30,
  p_offset integer default 0
)
returns setof public.prayer_feed
language sql
stable
security invoker
set search_path = public
as $$
  select * from public.prayer_feed
   where public.norm_text(title) like '%' || public.norm_text(p_term) || '%'
      or public.norm_text(body)  like '%' || public.norm_text(p_term) || '%'
   order by created_at desc
   limit least(coalesce(p_limit, 30), 100) offset coalesce(p_offset, 0);
$$;

grant execute on function public.search_prayers(text, integer, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Resgate de convite. É o portão de entrada do app: transforma um usuário
-- recém-registrado (is_approved = false) em obreiro aprovado.
--
-- security definer porque o usuário NÃO tem permissão de update no próprio
-- role/is_approved (senão qualquer um se promoveria a admin).
-- ---------------------------------------------------------------------------
create or replace function public.redeem_invite(invite_code text)
returns public.app_role
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.invites;
  v_uid    uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- for update: serializa resgates concorrentes, para max_uses não ser furado.
  select * into v_invite
    from public.invites
   where upper(code) = upper(trim(invite_code))
     and deleted_at is null
   for update;

  if not found                                            then raise exception 'INVITE_NOT_FOUND'; end if;
  if v_invite.revoked_at is not null                      then raise exception 'INVITE_REVOKED';   end if;
  if v_invite.expires_at is not null
     and v_invite.expires_at < now()                      then raise exception 'INVITE_EXPIRED';    end if;
  if v_invite.uses >= v_invite.max_uses                   then raise exception 'INVITE_EXHAUSTED';  end if;

  -- Idempotente: se já aprovado, não consome outro uso.
  if exists (select 1 from public.profiles
              where id = v_uid and is_approved) then
    return (select role from public.profiles where id = v_uid);
  end if;

  -- Libera o trigger protect_profile_privileges (§8) para esta transação.
  -- set_config com is_local = true expira no fim da transação, então a
  -- permissão não vaza para outras operações da mesma conexão.
  perform set_config('app.redeeming_invite', 'on', true);

  update public.profiles
     set role = v_invite.role,
         is_approved = true,
         updated_at = now()
   where id = v_uid;

  update public.invites
     set uses = uses + 1, updated_at = now()
   where id = v_invite.id;

  return v_invite.role;
end;
$$;

revoke all on function public.redeem_invite(text) from public, anon;
grant execute on function public.redeem_invite(text) to authenticated;
```

---

## §6 — Row Level Security

**Habilite RLS em todas as tabelas.** No Supabase, uma tabela sem RLS é
totalmente pública para a `anon key`.

```sql
alter table public.profiles            enable row level security;
alter table public.invites             enable row level security;
alter table public.scale_types         enable row level security;
alter table public.scale_managers      enable row level security;
alter table public.scale_assignments   enable row level security;
alter table public.events              enable row level security;
alter table public.weekly_slots        enable row level security;
alter table public.prayer_posts        enable row level security;
alter table public.prayer_interactions enable row level security;
alter table public.prayer_comments     enable row level security;
alter table public.announcements       enable row level security;
alter table public.base_info           enable row level security;
alter table public.social_links        enable row level security;
```

### 6.1 profiles

```sql
-- Todo usuário autenticado vê o próprio perfil (necessário para descobrir se
-- foi aprovado — antes disso ele não veria nada e ficaria em limbo).
create policy profiles_select_self on public.profiles
  for select to authenticated
  using (id = auth.uid());

-- Aprovados veem a lista de obreiros (para escolher responsáveis, ver autores).
create policy profiles_select_approved on public.profiles
  for select to authenticated
  using (public.is_approved() and deleted_at is null);

-- Edita o próprio perfil, MAS não pode mexer em role/is_approved.
-- O check é reforçado pelo trigger protect_profile_privileges (§8).
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy profiles_admin_all on public.profiles
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());
```

### 6.2 invites

```sql
-- Só admin lê/gera convites. Quem se cadastra NÃO consulta a tabela:
-- valida via RPC redeem_invite (security definer), que ignora RLS.
create policy invites_admin_all on public.invites
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());
```

### 6.3 Escalas

```sql
create policy scale_types_select on public.scale_types
  for select to authenticated
  using (public.is_approved() and deleted_at is null);

create policy scale_types_admin_write on public.scale_types
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy scale_managers_select on public.scale_managers
  for select to authenticated
  using (public.is_approved());

create policy scale_managers_admin_write on public.scale_managers
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---- O requisito central de permissão do app ----
create policy scale_assignments_select on public.scale_assignments
  for select to authenticated
  using (public.is_approved() and deleted_at is null);

create policy scale_assignments_insert on public.scale_assignments
  for insert to authenticated
  with check (public.manages_scale(scale_type_id));

-- using: pode alterar linhas da escala que gerencia hoje.
-- with check: não pode "mover" a linha para uma escala que não gerencia.
create policy scale_assignments_update on public.scale_assignments
  for update to authenticated
  using (public.manages_scale(scale_type_id))
  with check (public.manages_scale(scale_type_id));

-- Delete físico existe apenas para admin (limpeza). O app usa soft delete
-- (update de deleted_at), coberto pela policy de update acima.
create policy scale_assignments_delete on public.scale_assignments
  for delete to authenticated
  using (public.is_admin());
```

### 6.4 Agenda

```sql
create policy events_select on public.events
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy events_admin_write on public.events
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy weekly_slots_select on public.weekly_slots
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy weekly_slots_admin_write on public.weekly_slots
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
```

### 6.5 Mural de oração

```sql
create policy prayer_posts_select on public.prayer_posts
  for select to authenticated using (public.is_approved() and deleted_at is null);

create policy prayer_posts_insert on public.prayer_posts
  for insert to authenticated
  with check (public.is_approved() and author_id = auth.uid());

-- Autor edita o próprio; admin modera qualquer um.
create policy prayer_posts_update on public.prayer_posts
  for update to authenticated
  using (author_id = auth.uid() or public.is_admin())
  with check (author_id = auth.uid() or public.is_admin());

create policy prayer_posts_delete on public.prayer_posts
  for delete to authenticated
  using (author_id = auth.uid() or public.is_admin());

create policy prayer_interactions_select on public.prayer_interactions
  for select to authenticated using (public.is_approved());
create policy prayer_interactions_insert on public.prayer_interactions
  for insert to authenticated
  with check (public.is_approved() and user_id = auth.uid());
create policy prayer_interactions_delete on public.prayer_interactions
  for delete to authenticated using (user_id = auth.uid());

create policy prayer_comments_select on public.prayer_comments
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy prayer_comments_insert on public.prayer_comments
  for insert to authenticated
  with check (public.is_approved() and author_id = auth.uid());
create policy prayer_comments_update on public.prayer_comments
  for update to authenticated
  using (author_id = auth.uid() or public.is_admin())
  with check (author_id = auth.uid() or public.is_admin());
create policy prayer_comments_delete on public.prayer_comments
  for delete to authenticated using (author_id = auth.uid() or public.is_admin());
```

### 6.6 Início / institucional

```sql
create policy announcements_select on public.announcements
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy announcements_admin_write on public.announcements
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy base_info_select on public.base_info
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy base_info_admin_write on public.base_info
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy social_links_select on public.social_links
  for select to authenticated using (public.is_approved() and deleted_at is null);
create policy social_links_admin_write on public.social_links
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
```

---

## §7 — Storage

Criar os buckets pelo painel (Storage → New bucket) ou por SQL, ambos
**privados** — o app lê via URL assinada:

```sql
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false), ('event-covers', 'event-covers', false)
on conflict (id) do nothing;

-- Avatar: cada usuário só escreve na própria pasta "<uid>/...".
-- storage.foldername(name) devolve o array de pastas do caminho.
create policy avatars_read on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and public.is_approved());

create policy avatars_write_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_update_own on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy avatars_delete_own on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- Capas de evento: leitura para aprovados, escrita só admin.
create policy covers_read on storage.objects
  for select to authenticated
  using (bucket_id = 'event-covers' and public.is_approved());

create policy covers_admin_write on storage.objects
  for all to authenticated
  using (bucket_id = 'event-covers' and public.is_admin())
  with check (bucket_id = 'event-covers' and public.is_admin());
```

---

## §8 — Triggers

```sql
-- ---------------------------------------------------------------------------
-- updated_at automático. Sem isto o sync incremental não funciona: o cliente
-- não teria como saber que a linha mudou.
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'profiles','invites','scale_types','scale_managers','scale_assignments',
    'events','weekly_slots','prayer_posts','prayer_interactions',
    'prayer_comments','announcements','base_info','social_links'
  ] loop
    execute format(
      'create trigger %I_touch_updated_at before update on public.%I
         for each row execute function public.touch_updated_at()', t, t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Impede escalada de privilégio: um usuário comum não pode alterar o próprio
-- role nem is_approved, mesmo tendo permissão de update no perfil.
-- Defesa em profundidade — a policy já restringe, isto garante.
-- ---------------------------------------------------------------------------
create or replace function public.protect_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Exceção para a RPC redeem_invite, que precisa promover o próprio usuário.
  -- A flag é setada com is_local = true e morre no fim da transação.
  if coalesce(current_setting('app.redeeming_invite', true), 'off') = 'on' then
    return new;
  end if;

  if public.is_admin() then
    return new;
  end if;

  if new.role is distinct from old.role
     or new.is_approved is distinct from old.is_approved then
    raise exception 'FORBIDDEN_PRIVILEGE_CHANGE';
  end if;

  return new;
end;
$$;

create trigger profiles_protect_privileges
  before update on public.profiles
  for each row execute function public.protect_profile_privileges();
```

**Por que essa flag existe.** A `redeem_invite` é `security definer`, mas o
trigger avalia `is_admin()` — que é `false` para o obreiro se cadastrando. Sem a
exceção, o resgate de convite falharia com `FORBIDDEN_PRIVILEGE_CHANGE`. A
alternativa seria mover `role`/`is_approved` para uma tabela `profile_privileges`
sem permissão de update para `authenticated`; é mais puro, mas adiciona um join
em toda checagem de permissão. A flag transacional resolve com menos peça móvel.

**Cubra com os dois testes** (`§11`):
1. obreiro fazendo `update profiles set role='admin' where id = auth.uid()`
   → deve falhar com `FORBIDDEN_PRIVILEGE_CHANGE`;
2. obreiro chamando `select redeem_invite('VEREDAS2026')` → deve funcionar.

---

## §9 — Seeds (`supabase/seed.sql`)

Valores marcados com `TODO` devem ser confirmados com o solicitante
(`PLANO.md` §9) antes de ir para produção.

```sql
-- ---- Tipos de escala ----
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

  ('intercessao', 'Intercessão',
   'Turnos de intercessão.', 'volunteer_activism', 'weekly',
   array['06:00-07:00','12:00-13:00','18:00-19:00','21:00-22:00'], 4),

  ('cafe-da-gratidao', 'Café da Gratidão',
   'Escala do Café da Gratidão.', 'celebration', 'adhoc',
   array[]::text[], 5),

  -- Sem slots: o almoço é escalado como um grupo por dia, não por sub-área.
  ('almoco', 'Almoço',
   'Preparo do almoço da base.', 'restaurant', 'weekly',
   array[]::text[], 6)
on conflict (slug) do nothing;

-- ---- Dados da base (TODO: valores reais) ----
insert into public.base_info (key, label, value, ordering) values
  ('endereco', 'Endereço da base', 'TODO', 1),
  ('cep',      'CEP',              'TODO', 2),
  ('telefone', 'Telefone',         'TODO', 3),
  ('cnpj',     'CNPJ',             'TODO', 4)
on conflict (key) do nothing;

-- ---- Redes sociais (TODO: URLs reais) ----
insert into public.social_links (platform, url, ordering) values
  ('instagram', 'https://instagram.com/TODO', 1),
  ('facebook',  'https://facebook.com/TODO',  2),
  ('youtube',   'https://youtube.com/@TODO',  3)
on conflict do nothing;

-- ---- Cronograma semanal (TODO: cronograma real da base) ----
-- weekday: 1 = segunda ... 7 = domingo
insert into public.weekly_slots (weekday, starts_at, ends_at, title, location) values
  (1, '06:00', '07:00', 'Intercessão',      'Sala de oração'),
  (1, '08:00', '09:00', 'Café da manhã',    'Cozinha'),
  (3, '19:30', '21:00', 'Culto de oração',  'Salão')
on conflict do nothing;

-- ---- Convite inicial ----
insert into public.invites (code, role, max_uses, note)
values ('VEREDAS2026', 'obreiro', 20, 'Convite inicial dos obreiros')
on conflict do nothing;
```

**Após o seed, promova o admin manualmente** (crie a conta pelo app primeiro):

```sql
update public.profiles
   set role = 'admin', is_approved = true
 where email = 'TODO@exemplo.com';
```

---

## §10 — Realtime (opcional, Fase 10)

```sql
alter publication supabase_realtime add table public.prayer_posts;
alter publication supabase_realtime add table public.prayer_comments;
alter publication supabase_realtime add table public.prayer_interactions;
alter publication supabase_realtime add table public.scale_assignments;
alter publication supabase_realtime add table public.events;
alter publication supabase_realtime add table public.announcements;
```

O cliente **não** aplica o payload do Realtime direto no cache: usa o evento
apenas como gatilho para `syncService.pull(entity)`. Isso mantém um único
caminho de escrita no drift e evita divergência entre os dois mecanismos.

---

## §11 — Roteiro de validação do RLS (fim da Fase 1)

Execute no SQL Editor. `set local role authenticated` + `request.jwt.claims`
simulam um usuário logado.

```sql
-- Substitua pelos UUIDs reais de 3 usuários de teste.
--   :nao_aprovado  - cadastrado, convite não resgatado
--   :obreiro       - aprovado, gerencia 'servir-ao-todo'
--   :outro         - aprovado, não gerencia nada

-- Helper para simular um usuário:
-- set local role authenticated;
-- set local "request.jwt.claims" = '{"sub":"<uuid>","role":"authenticated"}';

begin;
  set local role authenticated;
  set local "request.jwt.claims" = '{"sub":"<uuid_nao_aprovado>","role":"authenticated"}';
  -- ESPERADO: 0 linhas
  select count(*) as deve_ser_zero from public.events;
  select count(*) as deve_ser_zero from public.scale_assignments;
  -- ESPERADO: 1 linha (vê o próprio perfil)
  select count(*) as deve_ser_um from public.profiles;
rollback;

begin;
  set local role authenticated;
  set local "request.jwt.claims" = '{"sub":"<uuid_outro>","role":"authenticated"}';
  -- ESPERADO: erro de RLS (não gerencia nenhuma escala)
  insert into public.scale_assignments (scale_type_id, starts_on, assignee_name)
  values ((select id from public.scale_types where slug='servir-ao-todo'),
          current_date, 'Teste');
rollback;

begin;
  set local role authenticated;
  set local "request.jwt.claims" = '{"sub":"<uuid_obreiro>","role":"authenticated"}';
  -- ESPERADO: sucesso
  insert into public.scale_assignments (scale_type_id, starts_on, assignee_name)
  values ((select id from public.scale_types where slug='servir-ao-todo'),
          current_date, 'Teste');
  -- ESPERADO: erro (gerencia servir-ao-todo, não lixo)
  insert into public.scale_assignments (scale_type_id, starts_on, assignee_name)
  values ((select id from public.scale_types where slug='lixo'),
          current_date, 'Teste');
rollback;

begin;
  set local role authenticated;
  set local "request.jwt.claims" = '{"sub":"<uuid_obreiro>","role":"authenticated"}';
  -- ESPERADO: erro FORBIDDEN_PRIVILEGE_CHANGE
  update public.profiles set role = 'admin' where id = '<uuid_obreiro>';
rollback;

begin;
  set local role authenticated;
  set local "request.jwt.claims" = '{"sub":"<uuid_nao_aprovado>","role":"authenticated"}';
  -- ESPERADO: sucesso, retornando 'obreiro'.
  -- Valida que a flag app.redeeming_invite libera o trigger (§8).
  select public.redeem_invite('VEREDAS2026');
  -- ESPERADO: is_approved = true
  select is_approved, role from public.profiles where id = '<uuid_nao_aprovado>';
rollback;
```

Os 5 blocos precisam se comportar exatamente como anotado. Se algum divergir,
**não avance para a Fase 2** — corrija a policy primeiro.

Os dois últimos blocos são complementares e ambos precisam passar: o obreiro
**não** pode se promover manualmente, **mas** o resgate de convite tem de
funcionar. Se apenas um deles passar, a flag transacional do §8 está errada.
