import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/repositories/outbox_helper.dart';

/// Repositório da tela Escalas — escrita de atribuições.
///
/// Toda escrita passa pelo `OutboxHelper`: aplica a mudança otimista no cache
/// e enfileira na outbox. O RLS no servidor garante que só o responsável pela
/// escala (ou admin) pode escrever — um 403 reverte o cache otimista.
class ScalesRepository {
  ScalesRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // --- Scale assignments ----------------------------------------------------

  /// Cria uma atribuição de escala.
  ///
  /// [assigneeId] ou [assigneeName] deve ser preenchido (o servidor valida).
  /// [startsOn] é guardado como DateTime à meia-noite local.
  Future<String> createAssignment({
    required String scaleTypeId,
    required DateTime startsOn,
    DateTime? endsOn,
    String? slot,
    String? task,
    String? assigneeId,
    String? assigneeName,
    String? notes,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await OutboxHelper.insert(
      db: _db,
      entity: 'scale_assignments',
      rowId: id,
      payload: {
        'id': id,
        'scale_type_id': scaleTypeId,
        'starts_on': _dateOnly(startsOn),
        'ends_on': endsOn != null ? _dateOnly(endsOn) : null,
        'slot': slot,
        'task': task,
        'assignee_id': assigneeId,
        'assignee_name': assigneeName,
        'notes': notes,
      },
      applyChange: () async {
        await _db.into(_db.scaleAssignmentRows).insertOnConflictUpdate(
              ScaleAssignmentRow(
                id: id,
                scaleTypeId: scaleTypeId,
                startsOn: _atMidnight(startsOn),
                endsOn: endsOn != null ? _atMidnight(endsOn) : null,
                slot: slot,
                task: task,
                assigneeId: assigneeId,
                assigneeName: assigneeName,
                notes: notes,
                updatedAt: now,
              ),
            );
      },
    );

    return id;
  }

  /// Edita uma atribuição existente.
  Future<void> updateAssignment({
    required String id,
    required String scaleTypeId,
    required DateTime startsOn,
    DateTime? endsOn,
    String? slot,
    String? task,
    String? assigneeId,
    String? assigneeName,
    String? notes,
  }) async {
    await OutboxHelper.update(
      db: _db,
      entity: 'scale_assignments',
      rowId: id,
      payload: {
        'scale_type_id': scaleTypeId,
        'starts_on': _dateOnly(startsOn),
        'ends_on': endsOn != null ? _dateOnly(endsOn) : null,
        'slot': slot,
        'task': task,
        'assignee_id': assigneeId,
        'assignee_name': assigneeName,
        'notes': notes,
      },
      applyChange: () async {
        final existing = await (_db.select(_db.scaleAssignmentRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (existing == null) return;

        await _db.into(_db.scaleAssignmentRows).insertOnConflictUpdate(
              existing.copyWith(
                scaleTypeId: scaleTypeId,
                startsOn: _atMidnight(startsOn),
                endsOn: Value(endsOn != null ? _atMidnight(endsOn) : null),
                slot: Value(slot),
                task: Value(task),
                assigneeId: Value(assigneeId),
                assigneeName: Value(assigneeName),
                notes: Value(notes),
                updatedAt: DateTime.now().toUtc(),
              ),
            );
      },
      queryExisting: () async {
        final row = await (_db.select(_db.scaleAssignmentRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  /// Remove uma atribuição (soft delete no servidor).
  Future<void> deleteAssignment(String id) async {
    await OutboxHelper.delete(
      db: _db,
      entity: 'scale_assignments',
      rowId: id,
      applyChange: () async {
        await (_db.delete(_db.scaleAssignmentRows)
              ..where((t) => t.id.equals(id)))
            .go();
      },
      queryExisting: () async {
        final row = await (_db.select(_db.scaleAssignmentRows)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        return row?.toJson();
      },
    );
  }

  // --- Helpers --------------------------------------------------------------

  /// Converte DateTime para string "YYYY-MM-DD" (formato `date` do PG).
  static String _dateOnly(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year.toString().padLeft(4, '0')}'
        '-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}';
  }

  /// DateTime à meia-noite local (para comparações por dia no cache).
  static DateTime _atMidnight(DateTime dt) {
    final d = dt.toLocal();
    return DateTime(d.year, d.month, d.day);
  }
}
