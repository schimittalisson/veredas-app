-- =========================================================================
-- Lápides de exclusão visíveis para o pull incremental
--
-- -------------------------------------------------------------------------
-- O bug
-- -------------------------------------------------------------------------
--
-- Um aviso ou slot do cronograma excluído por um admin continuava visível
-- **para sempre** no aparelho de todos os outros obreiros.
--
-- A cadeia tinha três peças que, isoladas, pareciam certas:
--
--   1. O app apagava com DELETE físico (`remote_source.dart`).
--   2. O pull incremental só aprende que uma linha morreu quando ela volta
--      com `deleted_at` preenchido (`sync_service.dart`).
--   3. Linha apagada fisicamente nunca volta. O pull não tem como distinguir
--      "foi excluída" de "não mudou desde a última sincronização".
--
-- Resultado: a linha sumia para quem apagou e sobrevivia em todo o resto.
--
-- -------------------------------------------------------------------------
-- O que já era o desenho
-- -------------------------------------------------------------------------
--
-- O schema sempre previu soft delete — as colunas `deleted_at` existem desde
-- a migration 0400, e o comentário da policy `scale_assignments_delete` (0600)
-- afirma "o app usa soft delete (update de deleted_at)". Só a implementação
-- nunca fez isso. Esta migration e a mudança no `OutboxWorker` alinham o
-- código ao desenho, em vez de mudar o desenho.
--
-- -------------------------------------------------------------------------
-- Por que mexer na RLS também
-- -------------------------------------------------------------------------
--
-- Fazer o app marcar `deleted_at` não basta: as policies de select filtram
-- `deleted_at is null`, então a lápide continuaria invisível e o pull seguiria
-- cego. As duas pontas precisam mudar juntas.
--
-- Só as tabelas **incrementais que o app exclui** entram aqui:
--
--   events, weekly_slots, announcements, scale_assignments
--
-- As demais mantêm o filtro de propósito:
--
--   - `profiles`, `documents`, `laundry_*`, `scale_managers`,
--     `prayer_interactions`, `prayer_feed` são sincronizadas por substituição
--     total, que reconcilia pela ausência. Deixar a lápide passar só faria
--     trafegar linha morta.
--   - `scale_types`, `invites`, `base_info`, `social_links` são incrementais
--     mas o app não tem caminho de exclusão para elas. Quando tiver, entram
--     nesta mesma lista.
--
-- Privacidade: a linha com lápide não revela nada que a linha viva já não
-- revelasse para o mesmo público, e o app a descarta do cache assim que a
-- enxerga — ela nunca chega à tela.
-- =========================================================================

-- events
drop policy if exists events_select on public.events;
create policy events_select on public.events
  for select to authenticated using (public.is_approved());

-- weekly_slots
drop policy if exists weekly_slots_select on public.weekly_slots;
create policy weekly_slots_select on public.weekly_slots
  for select to authenticated using (public.is_approved());

-- announcements
drop policy if exists announcements_select on public.announcements;
create policy announcements_select on public.announcements
  for select to authenticated using (public.is_approved());

-- scale_assignments
drop policy if exists scale_assignments_select on public.scale_assignments;
create policy scale_assignments_select on public.scale_assignments
  for select to authenticated using (public.is_approved());

-- -------------------------------------------------------------------------
-- Bug latente corrigido de quebra
-- -------------------------------------------------------------------------
--
-- `scale_assignments_delete` permite apagar só para `is_admin()`, mas a UI
-- libera a edição de escala para os **responsáveis** (`manages_scale`). No dia
-- em que a tela ganhasse um botão de excluir atribuição, um responsável não
-- admin veria a atribuição **voltar**: o servidor devolveria 0 linhas, o
-- outbox leria como recusa e reverteria o cache otimista.
--
-- Com soft delete o caminho passa a ser um UPDATE, e a policy
-- `scale_assignments_update` já cobre `manages_scale(scale_type_id)` — ou
-- seja, o responsável consegue excluir e o admin continua conseguindo. A
-- policy de delete físico fica como está, para a limpeza manual do admin.
--
-- Nada a fazer aqui além de registrar: a correção veio de graça com a mudança.
