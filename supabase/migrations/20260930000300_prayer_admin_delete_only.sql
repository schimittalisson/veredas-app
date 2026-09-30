-- =========================================================================
-- Mural: o admin apaga o pedido de outra pessoa, mas não o edita
--
-- A policy `prayer_posts_update` (migration 0600) deixa o admin fazer UPDATE
-- em qualquer pedido — "admin modera qualquer um". Ela precisa continuar
-- deixando, porque apagar é soft delete: um UPDATE de `deleted_at`. Mas uma
-- policy não distingue coluna, então o mesmo UPDATE que apaga também
-- permitia reescrever o título e o texto de quem registrou a oração.
--
-- Decisão do solicitante: o mural registra orações de cada pessoa ("hoje orei
-- por Portugal"), e o admin não deve poder mudar o que outra pessoa escreveu —
-- só remover. Marcar como respondido entra na mesma regra: é o autor contando
-- que a oração dele foi respondida.
--
-- O app já não oferece "Editar" nem "Marcar como respondido" no pedido alheio;
-- este trigger é o que garante isso no servidor, porque esconder o botão não
-- é controle de acesso.
--
-- Por que trigger e não policy: a regra é "quem não é o autor só pode mexer em
-- `deleted_at`", e RLS não enxerga quais colunas mudaram. Mesmo mecanismo de
-- `protect_profile_privileges`.
-- =========================================================================

create or replace function public.protect_prayer_post_content()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Sem auth.uid(): acesso direto ao banco (SQL Editor, migration) ou um RPC
  -- que roda sem usuário. Mesma exceção de `protect_profile_privileges`.
  if auth.uid() is null or old.author_id = auth.uid() then
    return new;
  end if;

  if new.title        is distinct from old.title
     or new.body         is distinct from old.body
     or new.is_anonymous is distinct from old.is_anonymous
     or new.answered_at  is distinct from old.answered_at
     or new.answer_note  is distinct from old.answer_note
     or new.author_id    is distinct from old.author_id then
    raise exception 'FORBIDDEN_POST_EDIT';
  end if;

  return new;
end;
$$;

create trigger prayer_posts_protect_content
  before update on public.prayer_posts
  for each row execute function public.protect_prayer_post_content();
