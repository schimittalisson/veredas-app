import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Providers da tela Escalas — streams do drift sobre o cache local.

/// Tipos de escala ativos, ordenados por `ordering` (define a ordem das abas).
final activeScaleTypesProvider = StreamProvider<List<ScaleTypeRow>>((ref) {
  return ref.watch(scalesDaoProvider).watchActiveScaleTypes();
});

/// Todos os responsáveis por escala (escala → usuários).
final scaleManagersProvider = StreamProvider<List<ScaleManagerRow>>((ref) {
  return ref.watch(scalesDaoProvider).watchScaleManagers();
});

/// IDs de tipos de escala que o usuário logado gerencia.
///
/// Derivado de `scale_managers` filtrado por `userId == currentUser.id`.
/// Usado pelo `canEditScale` para decidir se mostra o FAB.
final managedScaleTypeIdsProvider = Provider<Set<String>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const {};
  final managers = ref.watch(scaleManagersProvider).value ?? const [];
  return managers
      .where((m) => m.userId == userId)
      .map((m) => m.scaleTypeId)
      .toSet();
});

/// Argumento para [assignmentsProvider] — tipo de escala + intervalo de datas.
typedef AssignmentQuery = ({String scaleTypeId, DateTime from, DateTime to});

/// Atribuições de um tipo de escala num intervalo de datas.
///
/// Usa um record `AssignmentQuery` como argumento family porque o Riverpod 3
/// não tem `family3`. O record é comparável por valor, então o cache funciona.
final assignmentsProvider =
    StreamProvider.family<List<ScaleAssignmentRow>, AssignmentQuery>((ref, q) {
  return ref.watch(scalesDaoProvider).watchAssignments(q.scaleTypeId, q.from, q.to);
});

/// Todas as atribuições de um tipo de escala (para adhoc, sem seletor).
final allAssignmentsProvider =
    StreamProvider.family<List<ScaleAssignmentRow>, String>((ref, scaleTypeId) {
  return ref.watch(scalesDaoProvider).watchAllAssignments(scaleTypeId);
});

/// Conta quantas atribuições o usuário logado tem num intervalo.
///
/// Usado para o resumo "Você está escalado N× neste período".
final myAssignmentCountProvider =
    FutureProvider.family<int, AssignmentQuery>((ref, q) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return 0;
  final assignments =
      ref.watch(assignmentsProvider(q)).value ?? const [];
  return assignments.where((a) => a.assigneeId == userId).length;
});
