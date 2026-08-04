-- =========================================================================
-- §2 — Perfis e convites
-- =========================================================================

-- -------------------------------------------------------------------------
-- profiles: espelho de auth.users com os dados de domínio.
-- Nunca escrever em auth.users diretamente.
-- -------------------------------------------------------------------------
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

-- -------------------------------------------------------------------------
-- Cria o profile automaticamente quando um usuário se registra no Auth.
-- security definer: roda com privilégios do owner, ignorando RLS — o usuário
-- recém-criado ainda não tem permissão de insert em profiles.
-- -------------------------------------------------------------------------
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

-- -------------------------------------------------------------------------
-- invites: cadastro só acontece com um código válido.
-- A tabela nunca é consultada pelo cliente que se cadastra — a validação
-- passa pela RPC redeem_invite (migration 0500), que é security definer.
-- -------------------------------------------------------------------------
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

-- Comparação de código é case-insensitive: o índice único também precisa ser,
-- senão 'veredas2026' e 'VEREDAS2026' coexistiriam como convites distintos.
create unique index invites_code_key on public.invites (upper(code));
