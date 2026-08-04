-- =========================================================================
-- §3 — Funções auxiliares de permissão
--
-- PONTO CRÍTICO: uma policy em `profiles` que faça `select ... from profiles`
-- causa recursão infinita de RLS (erro `infinite recursion detected in
-- policy`). A solução é encapsular a consulta em funções `security definer`,
-- que rodam com privilégios do owner e portanto não reavaliam RLS.
--
-- `manages_scale` NÃO está aqui: ela referencia public.scale_managers, criada
-- na 0400. Com check_function_bodies = on (padrão no Supabase), o corpo de uma
-- função `language sql` É validado no CREATE FUNCTION, então criá-la antes da
-- tabela falha com `relation "public.scale_managers" does not exist`.
-- Ela vive na migration 0450, aplicada depois das tabelas de domínio.
-- =========================================================================

-- Está aprovado? (base de toda leitura no app)
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

-- -------------------------------------------------------------------------
-- Normalização para busca: minúsculas sem acento.
--
-- A forma de DOIS argumentos de unaccent (dicionário explícito) é obrigatória
-- aqui: a de um argumento é apenas STABLE, porque resolve o dicionário default
-- em tempo de execução, e uma função STABLE não pode ser usada em índice.
-- Passando o regdictionary explicitamente, a chamada é IMMUTABLE e o índice
-- de expressão da 0400 funciona.
-- -------------------------------------------------------------------------
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
revoke all on function public.is_admin()    from public;
grant execute on function public.is_approved()   to authenticated;
grant execute on function public.is_admin()      to authenticated;
grant execute on function public.norm_text(text) to authenticated;
