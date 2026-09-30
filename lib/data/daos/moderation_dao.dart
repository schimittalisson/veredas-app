import 'package:drift/drift.dart';

import 'package:veredas/data/local/app_database.dart';

/// Uma pessoa bloqueada, com o nome vindo do cache de perfis.
///
/// [name] é nulo quando o perfil ainda não chegou ao cache — a tela mostra um
/// rótulo genérico em vez de esconder a linha, senão não haveria como
/// desbloquear.
typedef BlockedUser = ({String id, String? name});

/// DAO da moderação do mural: bloqueios e denúncias.
class ModerationDao {
  ModerationDao(this.db);

  final AppDatabase db;

  /// Ids de quem o usuário logado bloqueou.
  Stream<Set<String>> watchBlockedIds() {
    return db
        .select(db.userBlockRows)
        .watch()
        .map((rows) => {for (final r in rows) r.blockedId});
  }

  /// Bloqueados com nome, em ordem alfabética.
  Stream<List<BlockedUser>> watchBlockedUsers() {
    final query = db.select(db.userBlockRows).join([
      leftOuterJoin(
        db.profileRows,
        db.profileRows.id.equalsExp(db.userBlockRows.blockedId),
      ),
    ]);
    return query.watch().map((rows) {
      final list = [
        for (final r in rows)
          (
            id: r.readTable(db.userBlockRows).blockedId,
            name: r.readTableOrNull(db.profileRows)?.fullName,
          ),
      ];
      list.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
      return list;
    });
  }

  /// Posts que [reporterId] denunciou. Resolvidos ou não: quem denunciou não
  /// quer voltar a ver o post só porque o admin decidiu mantê-lo.
  Stream<Set<String>> watchReportedPostIds(String reporterId) {
    return (db.select(db.contentReportRows)
          ..where((t) => t.reporterId.equals(reporterId)))
        .watch()
        .map((rows) => {for (final r in rows) r.postId});
  }

  /// Denúncias ainda sem decisão, as mais antigas primeiro — é a ordem em que
  /// o prazo de 24 horas vence.
  Stream<List<ContentReportRow>> watchPendingReports() {
    return (db.select(db.contentReportRows)
          ..where((t) => t.resolvedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }
}
