import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/daos/moderation_dao.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Providers da moderação do mural — streams do drift sobre o cache local.

/// Ids de quem o usuário logado bloqueou.
final blockedUserIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(moderationDaoProvider).watchBlockedIds();
});

/// Bloqueados com nome, para a tela "Usuários bloqueados".
final blockedUsersProvider = StreamProvider<List<BlockedUser>>((ref) {
  return ref.watch(moderationDaoProvider).watchBlockedUsers();
});

/// Posts que o usuário logado denunciou.
///
/// Filtra por `reporterId` mesmo o RLS já devolvendo só as próprias denúncias
/// a um obreiro: para o admin o cache tem as denúncias de todo mundo, e sem o
/// filtro o feed dele esconderia tudo o que qualquer pessoa denunciou —
/// justamente o que ele precisa ver para moderar.
///
/// Para o admin, nem as próprias denúncias escondem nada: é ele quem decide
/// sobre elas, e um post que ele denunciou e depois resolveu manter sumiria
/// só do mural dele, sem como voltar.
final reportedPostIdsProvider = StreamProvider<Set<String>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null || ref.watch(isAdminProvider)) {
    return Stream.value(const {});
  }
  return ref.watch(moderationDaoProvider).watchReportedPostIds(userId);
});

/// Denúncias pendentes (tela Administração → Denúncias).
final pendingReportsProvider = StreamProvider<List<ContentReportRow>>((ref) {
  return ref.watch(moderationDaoProvider).watchPendingReports();
});
