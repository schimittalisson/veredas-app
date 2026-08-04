-- =========================================================================
-- §3 (continuação) — manages_scale
--
-- Separada da 0300 de propósito. Esta função referencia public.scale_managers,
-- criada na 0400. Com check_function_bodies = on (o padrão no Supabase), o
-- corpo de uma função `language sql` é validado no CREATE FUNCTION, então
-- criá-la antes da tabela falharia com:
--   ERROR: relation "public.scale_managers" does not exist
--
-- É a única função de permissão que depende de uma tabela de domínio, por isso
-- é a única que precisa vir depois delas. Ela é consumida pelas policies de
-- scale_assignments na 0600.
-- =========================================================================

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

revoke all on function public.manages_scale(uuid) from public;
grant execute on function public.manages_scale(uuid) to authenticated;
