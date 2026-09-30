-- =========================================================================
-- Anonimato do mural: o autor de um pedido anônimo não vaza mais pela API
--
-- -------------------------------------------------------------------------
-- O vazamento
-- -------------------------------------------------------------------------
--
-- A view `prayer_feed` escondia `author_name` e `author_avatar_url` de pedido
-- anônimo, mas devolvia `author_id` para qualquer obreiro aprovado. E a
-- própria tabela `prayer_posts` era legível por todos os aprovados, com a
-- coluna. Quem consultasse a API direto (a anon key está no app) cruzava o id
-- com `profiles` e descobria quem escreveu. Pelo app não aparecia — mas o app
-- não é a fronteira de segurança, o RLS é.
--
-- Fechar só a view não bastaria: a tabela continuaria aberta. As duas pontas
-- mudam juntas.
--
-- -------------------------------------------------------------------------
-- 1. `prayer_posts`: cada um lê só o que escreveu (e o admin, tudo)
-- -------------------------------------------------------------------------
--
-- O feed passa a ser servido só pela view (abaixo). A leitura direta da
-- tabela fica para o autor e o admin — que é exatamente o que o app precisa:
-- as escritas do outbox usam `update ... returning` (o `.select()` de
-- `remote_source.dart`), e o RETURNING exige que a linha passe nesta policy.
--
-- **Isto também conserta a exclusão de pedido, que nunca funcionou.** A
-- policy antiga tinha `deleted_at is null`, e o soft delete gera uma linha
-- nova com `deleted_at` preenchido: o RETURNING a reprovava com 42501, o
-- outbox revertia o cache, e o pedido voltava no sync seguinte com o banner
-- de erro. O harness não pegava porque testava o UPDATE sem RETURNING.
-- Sem o filtro aqui, a lápide passa — e quem a lê é só o autor ou o admin.
--
-- O admin continua podendo ler o autor de um pedido anônimo pela API: ele
-- precisa da linha inteira para moderar (editar, apagar), e a denúncia já
-- guarda o autor para ele. O anonimato é em relação aos outros obreiros.

drop policy if exists prayer_posts_select on public.prayer_posts;
create policy prayer_posts_select on public.prayer_posts
  for select to authenticated
  using (public.is_approved()
         and (author_id = auth.uid() or public.is_admin()));

-- -------------------------------------------------------------------------
-- 2. `prayer_feed` passa a rodar com os privilégios do dono
-- -------------------------------------------------------------------------
--
-- Com `security_invoker = true`, a view herdaria a policy nova acima e cada
-- pessoa só veria os próprios posts. Agora ela lê a tabela como dona, e por
-- isso **refaz à mão os filtros que o RLS fazia**:
--
--   - `public.is_approved()`: sem isto, a view vazaria o mural para quem
--     ainda não foi aprovado (e para o role `anon`). É o motivo do aviso
--     "não remova" que existia na migration 0500 — o aviso continua valendo,
--     só mudou de lugar.
--   - `deleted_at is null` e o filtro de `user_blocks`, como antes.
--
-- `author_id` de pedido anônimo sai como o UUID nulo (zeros), exceto para o
-- próprio autor, que precisa dele para o app oferecer "Editar" e "Excluir".
-- Zeros e não `null` por compatibilidade: o app instalado guarda `authorId`
-- como coluna obrigatória, e um null derrubaria o pull do mural nesses
-- aparelhos até todo mundo atualizar. O UUID nulo não é id de ninguém, então
-- não bate com o usuário logado nem casa com perfil nenhum.
--
-- Efeito colateral, e desejado: o `join profiles` deixa de passar pelo RLS de
-- `profiles`, que esconde perfis removidos. Antes, os pedidos de alguém
-- removido da base sumiam do mural. O mural registra orações feitas ("hoje
-- orei por Portugal"), e outras pessoas continuam orando pelo mesmo motivo —
-- a oração não deixa de ter existido porque quem a registrou saiu. Por decisão
-- do solicitante, os pedidos ficam. (Quem exclui a própria conta apaga os
-- pedidos pelo `delete_own_account()`, e esses continuam saindo.)

create or replace view public.prayer_feed as
select
  p.id,
  case when p.is_anonymous and p.author_id is distinct from auth.uid()
       then '00000000-0000-0000-0000-000000000000'::uuid
       else p.author_id
  end as author_id,
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
where public.is_approved()
  and p.deleted_at is null
  -- Compara com o autor REAL: o bloqueio continua valendo mesmo que a pessoa
  -- bloqueada passe a publicar como anônima.
  and not exists (select 1 from public.user_blocks b
                   where b.blocker_id = auth.uid()
                     and b.blocked_id = p.author_id);

-- `create or replace` não mexe nas opções de uma view existente; é o ALTER
-- que tira o `security_invoker = true` da migration 0500.
alter view public.prayer_feed reset (security_invoker);

revoke all on public.prayer_feed from anon;
grant select on public.prayer_feed to authenticated;
