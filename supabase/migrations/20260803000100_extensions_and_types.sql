-- =========================================================================
-- §1 — Extensões e tipos
--
-- pg_trgm  : índice trigram para a busca por título no mural de oração.
-- unaccent : normalização de acentos, para "cura" encontrar "curá".
--
-- Ambas vão para o schema `extensions`, que é a convenção do Supabase.
-- As referências nas migrations seguintes usam o prefixo `extensions.`.
-- Confira o schema real antes de aplicar a 0300 e a 0400 (ver supabase/README.md).
-- =========================================================================

create extension if not exists pg_trgm  with schema extensions;
create extension if not exists unaccent with schema extensions;

-- Papéis globais. "Responsável por escala" NÃO é um papel global: é uma
-- atribuição por tipo de escala, na tabela scale_managers (migration 0400).
do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_role') then
    create type public.app_role as enum ('admin', 'obreiro');
  end if;
end;
$$;
