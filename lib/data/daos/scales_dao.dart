import 'package:drift/drift.dart';

import 'package:veredas/data/local/app_database.dart';

/// DAO da tela Escalas: tipos de escala, responsáveis e atribuições.
class ScalesDao {
  ScalesDao(this.db);

  final AppDatabase db;

  // --- Scale types (as abas da TabBar) -------------------------------------

  /// Tipos de escala ativos, ordenados por `ordering` (define a ordem das
  /// abas). Inativos são ocultados — desativar uma escala é como apagar para
  /// a UI, sem perder o histórico.
  Stream<List<ScaleTypeRow>> watchActiveScaleTypes() {
    return (db.select(db.scaleTypeRows)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.ordering)]))
        .watch();
  }

  Stream<List<ScaleTypeRow>> watchAllScaleTypes() {
    return (db.select(db.scaleTypeRows)
          ..orderBy([(t) => OrderingTerm.asc(t.ordering)]))
        .watch();
  }

  Future<ScaleTypeRow?> getScaleType(String id) {
    return (db.select(db.scaleTypeRows)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertScaleType(ScaleTypeRow row) {
    return db.into(db.scaleTypeRows).insertOnConflictUpdate(row);
  }

  Future<void> removeScaleType(String id) {
    return (db.delete(db.scaleTypeRows)..where((t) => t.id.equals(id))).go();
  }

  // --- Scale managers (quem pode editar cada escala) -----------------------

  Stream<List<ScaleManagerRow>> watchScaleManagers() {
    return db.select(db.scaleManagerRows).watch();
  }

  /// Responsáveis por um tipo de escala específico.
  Stream<List<ScaleManagerRow>> watchManagersForScale(String scaleTypeId) {
    return (db.select(db.scaleManagerRows)
          ..where((t) => t.scaleTypeId.equals(scaleTypeId)))
        .watch();
  }

  /// Tipos de escala que um usuário gerencia.
  Stream<List<ScaleManagerRow>> watchManagedScales(String userId) {
    return (db.select(db.scaleManagerRows)
          ..where((t) => t.userId.equals(userId)))
        .watch();
  }

  Future<void> upsertScaleManager(ScaleManagerRow row) {
    return db.into(db.scaleManagerRows).insertOnConflictUpdate(row);
  }

  Future<void> removeScaleManager(String scaleTypeId, String userId) {
    return (db.delete(db.scaleManagerRows)
          ..where(
            (t) => t.scaleTypeId.equals(scaleTypeId) & t.userId.equals(userId),
          ))
        .go();
  }

  // --- Scale assignments (as atribuições) ----------------------------------

  /// Atribuições de um tipo de escala num intervalo de datas.
  Stream<List<ScaleAssignmentRow>> watchAssignments(
    String scaleTypeId,
    DateTime from,
    DateTime to,
  ) {
    return (db.select(db.scaleAssignmentRows)
          ..where(
            (t) =>
                t.scaleTypeId.equals(scaleTypeId) &
                t.startsOn.isBetweenValues(from, to),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startsOn)]))
        .watch();
  }

  /// Todas as atribuições de um tipo de escala.
  Stream<List<ScaleAssignmentRow>> watchAllAssignments(
    String scaleTypeId,
  ) {
    return (db.select(db.scaleAssignmentRows)
          ..where((t) => t.scaleTypeId.equals(scaleTypeId))
          ..orderBy([(t) => OrderingTerm.asc(t.startsOn)]))
        .watch();
  }

  Future<ScaleAssignmentRow?> getAssignment(String id) {
    return (db.select(db.scaleAssignmentRows)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertAssignment(ScaleAssignmentRow row) {
    return db.into(db.scaleAssignmentRows).insertOnConflictUpdate(row);
  }

  Future<void> removeAssignment(String id) {
    return (db.delete(db.scaleAssignmentRows)
          ..where((t) => t.id.equals(id)))
        .go();
  }
}
