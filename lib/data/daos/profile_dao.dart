import 'package:drift/drift.dart';

import 'package:veredas/data/local/app_database.dart';

/// DAO de perfis e convites (usado pela Fase 3 de auth e pela Fase 9 de admin).
class ProfileDao {
  ProfileDao(this.db);

  final AppDatabase db;

  // --- Profiles ------------------------------------------------------------

  /// Todos os perfis, ordenados por nome.
  Stream<List<ProfileRow>> watchProfiles() {
    return (db.select(db.profileRows)
          ..orderBy([(t) => OrderingTerm.asc(t.fullName)]))
        .watch();
  }

  /// Perfis pendentes de aprovação (`is_approved = false`).
  Stream<List<ProfileRow>> watchPendingProfiles() {
    return (db.select(db.profileRows)
          ..where((t) => t.isApproved.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.fullName)]))
        .watch();
  }

  Future<ProfileRow?> getProfile(String id) {
    return (db.select(db.profileRows)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertProfile(ProfileRow row) {
    return db.into(db.profileRows).insertOnConflictUpdate(row);
  }

  Future<void> removeProfile(String id) {
    return (db.delete(db.profileRows)..where((t) => t.id.equals(id))).go();
  }

  // --- Invites -------------------------------------------------------------

  Stream<List<InviteRow>> watchInvites() {
    return (db.select(db.inviteRows)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<InviteRow?> getInvite(String id) {
    return (db.select(db.inviteRows)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertInvite(InviteRow row) {
    return db.into(db.inviteRows).insertOnConflictUpdate(row);
  }

  Future<void> removeInvite(String id) {
    return (db.delete(db.inviteRows)..where((t) => t.id.equals(id))).go();
  }
}
