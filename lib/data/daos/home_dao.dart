import 'package:drift/drift.dart';

import 'package:veredas/data/local/app_database.dart';

/// DAO da tela Início: avisos, dados da base, links sociais.
///
/// Leitura via `Stream` (reativo ao drift); escrita local via `Future`. A
/// escrita que vai ao servidor passa pelo `OutboxHelper` no repositório, não
/// aqui — o DAO só toca no cache local.
class HomeDao {
  HomeDao(this.db);

  final AppDatabase db;

  // --- Announcements (avisos) ----------------------------------------------

  /// Avisos ordenados: fixados primeiro, depois por data decrescente.
  Stream<List<AnnouncementRow>> watchAnnouncements() {
    return (db.select(db.announcementRows)
          ..orderBy([
            (t) => OrderingTerm.desc(t.pinned),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch();
  }

  Future<AnnouncementRow?> getAnnouncement(String id) {
    return (db.select(db.announcementRows)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertAnnouncement(AnnouncementRow row) {
    return db.into(db.announcementRows).insertOnConflictUpdate(row);
  }

  Future<void> removeAnnouncement(String id) {
    return (db.delete(db.announcementRows)..where((t) => t.id.equals(id))).go();
  }

  // --- Base info (dados da base) -------------------------------------------

  Stream<List<BaseInfoRow>> watchBaseInfo() {
    return (db.select(db.baseInfoRows)
          ..orderBy([(t) => OrderingTerm.asc(t.ordering)]))
        .watch();
  }

  Future<void> upsertBaseInfo(BaseInfoRow row) {
    return db.into(db.baseInfoRows).insertOnConflictUpdate(row);
  }

  Future<void> removeBaseInfo(String id) {
    return (db.delete(db.baseInfoRows)..where((t) => t.id.equals(id))).go();
  }

  // --- Social links --------------------------------------------------------

  Stream<List<SocialLinkRow>> watchSocialLinks() {
    return (db.select(db.socialLinkRows)
          ..orderBy([(t) => OrderingTerm.asc(t.ordering)]))
        .watch();
  }

  Future<void> upsertSocialLink(SocialLinkRow row) {
    return db.into(db.socialLinkRows).insertOnConflictUpdate(row);
  }

  Future<void> removeSocialLink(String id) {
    return (db.delete(db.socialLinkRows)..where((t) => t.id.equals(id))).go();
  }
}
