import 'package:drift/drift.dart';

import 'package:veredas/data/local/app_database.dart';

/// DAO do mural de oração: feed (view) e comentários.
class PrayerDao {
  PrayerDao(this.db);

  final AppDatabase db;

  // --- Prayer feed (view agregada) -----------------------------------------

  /// Feed completo, posts mais recentes primeiro.
  Stream<List<PrayerFeedRow>> watchFeed() {
    return (db.select(db.prayerFeedRows)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<PrayerFeedRow?> getPost(String id) {
    return (db.select(db.prayerFeedRows)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Atualiza otimistamente os contadores de "estou orando" na linha cacheada.
  ///
  /// O `prayer_interactions` não é cacheado (é DELETE físico). A escrita de
  /// "estou orando" ajusta `prayingCount` e `isPraying` direto nesta linha, e
  /// a entrada na outbox envia o INSERT/DELETE ao servidor. O próximo pull
  /// (fullReplace da view) corrige qualquer divergência.
  Future<void> togglePraying(PrayerFeedRow row, bool isNowPraying) {
    return db.into(db.prayerFeedRows).insertOnConflictUpdate(
          row.copyWith(
            isPraying: isNowPraying,
            prayingCount:
                isNowPraying ? row.prayingCount + 1 : row.prayingCount - 1,
          ),
        );
  }

  Future<void> upsertPost(PrayerFeedRow row) {
    return db.into(db.prayerFeedRows).insertOnConflictUpdate(row);
  }

  Future<void> removePost(String id) {
    return (db.delete(db.prayerFeedRows)..where((t) => t.id.equals(id))).go();
  }

  // --- Prayer comments -----------------------------------------------------

  Stream<List<PrayerCommentRow>> watchComments(String postId) {
    return (db.select(db.prayerCommentRows)
          ..where((t) => t.postId.equals(postId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<PrayerCommentRow?> getComment(String id) {
    return (db.select(db.prayerCommentRows)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertComment(PrayerCommentRow row) {
    return db.into(db.prayerCommentRows).insertOnConflictUpdate(row);
  }

  Future<void> removeComment(String id) {
    return (db.delete(db.prayerCommentRows)..where((t) => t.id.equals(id)))
        .go();
  }
}
