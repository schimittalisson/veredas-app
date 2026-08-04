-- Stubs que o Supabase fornece de fábrica e que um Postgres cru não tem.
-- Serve APENAS para validar sintaxe/dependências das migrations localmente.
-- Nada aqui vai para o Supabase.

create schema if not exists extensions;
create schema if not exists auth;
create schema if not exists storage;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end;
$$;

create table if not exists auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text,
  raw_user_meta_data jsonb default '{}'::jsonb
);

-- No Supabase real isto lê o claim `sub` do JWT.
--
-- O nullif() externo é essencial: quando uma transação que fez
-- `set local "request.jwt.claims"` termina, o GUC volta para STRING VAZIA (não
-- para NULL), e `''::jsonb` falha com `invalid input syntax for type json`.
-- Sem esse guard, qualquer statement fora de um act_as() quebra — inclusive o
-- caminho `auth.uid() is null` que o bootstrap do admin depende.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', ''
  )::uuid;
$$;

create table if not exists storage.buckets (
  id     text primary key,
  name   text not null,
  public boolean not null default false
);

create table if not exists storage.objects (
  id        uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name      text not null,
  owner     uuid
);

alter table storage.objects enable row level security;

create or replace function storage.foldername(name text)
returns text[]
language sql
immutable
as $$
  select string_to_array(name, '/');
$$;
