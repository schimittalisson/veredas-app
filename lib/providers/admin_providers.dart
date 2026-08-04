import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Providers da Administração — streams do drift sobre o cache local.
///
/// As ações (aprovar, revogar, criar convite, etc.) são escritas diretas
/// ao Supabase via RPC, não pela outbox — são operações administrativas
/// que só admin faz, e o conflito é impossível (só admin escreve). O
/// cache é atualizado pelo próximo pull.

/// Todos os perfis, ordenados por nome.
final allProfilesProvider = StreamProvider<List<ProfileRow>>((ref) {
  return ref.watch(profileDaoProvider).watchProfiles();
});

/// Perfis pendentes de aprovação (is_approved = false).
final pendingProfilesProvider = Provider<List<ProfileRow>>((ref) {
  final profiles = ref.watch(allProfilesProvider).value ?? const [];
  return profiles.where((p) => !p.isApproved).toList();
});

/// Perfis aprovados, ordenados por nome.
final approvedProfilesProvider = Provider<List<ProfileRow>>((ref) {
  final profiles = ref.watch(allProfilesProvider).value ?? const [];
  return profiles.where((p) => p.isApproved).toList();
});

/// Todos os convites, ordenados por criação decrescente.
final allInvitesProvider = StreamProvider<List<InviteRow>>((ref) {
  return ref.watch(profileDaoProvider).watchInvites();
});

/// Todos os responsáveis por escala.
final allScaleManagersProvider = StreamProvider<List<ScaleManagerRow>>((ref) {
  return ref.watch(scalesDaoProvider).watchScaleManagers();
});

/// Responsáveis agrupados por scaleTypeId.
final scaleManagersByTypeProvider =
    Provider<Map<String, List<ScaleManagerRow>>>((ref) {
  final managers = ref.watch(allScaleManagersProvider).value ?? const [];
  final map = <String, List<ScaleManagerRow>>{};
  for (final m in managers) {
    (map[m.scaleTypeId] ??= []).add(m);
  }
  return map;
});

/// Tipos de escala (todos, incluindo inativos) para a tela de admin.
final allScaleTypesProvider = StreamProvider<List<ScaleTypeRow>>((ref) {
  return ref.watch(scalesDaoProvider).watchAllScaleTypes();
});
