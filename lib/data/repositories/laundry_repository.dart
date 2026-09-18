import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/remote/laundry_service.dart';
import 'package:veredas/data/repositories/outbox_helper.dart';

/// Escritas da lavanderia.
///
/// **Dois caminhos diferentes, de propósito:**
///
/// - O **cadastro** (máquinas, faixas de horário, intervalos) é administração
///   comum: passa pelo `OutboxHelper`, como todo o resto do app. Um admin pode
///   cadastrar offline e a fila sobe depois.
///
/// - **Reservar e cancelar** vão direto ao servidor, via [LaundryService]. A
///   razão está documentada lá: a vaga é disputada, e a resposta do servidor é
///   a informação que interessa. É a exceção consciente à regra "toda escrita
///   passa pela outbox" que o `AGENTS.md` §6 exige comentar.
class LaundryRepository {
  LaundryRepository(this._db, this._service);

  final AppDatabase _db;
  final LaundryService _service;
  static const _uuid = Uuid();

  // --- Reservas (direto ao servidor) -----------------------------------------

  /// Reserva uma célula da grade. Devolve o id da reserva.
  ///
  /// Não escreve no cache: quem traz a reserva de volta é o pull que a tela
  /// dispara em seguida. Gravar otimista aqui pintaria a célula como "sua"
  /// antes de o servidor confirmar — e, se outra pessoa tivesse levado o
  /// horário, seria preciso despintar, que é exatamente a confusão que esta
  /// feature precisa evitar.
  Future<String> reserve({
    required String machineId,
    required String timeSlotId,
    required DateTime onDate,
  }) {
    return _service.reserve(
      machineId: machineId,
      timeSlotId: timeSlotId,
      onDate: onDate,
    );
  }

  /// Cancela uma reserva. Só o dono, ou um admin — quem valida é a RPC.
  Future<void> cancelReservation(String reservationId) {
    return _service.cancel(reservationId);
  }

  // --- Máquinas (outbox) ------------------------------------------------------

  Future<String> createMachine({
    required String name,
    String? note,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    final existing = await _db.select(_db.laundryMachineRows).get();
    final ordering =
        existing.fold<int>(0, (max, m) => m.ordering > max ? m.ordering : max) + 1;

    await OutboxHelper.insert(
      db: _db,
      entity: 'laundry_machines',
      rowId: id,
      payload: {
        'id': id,
        'name': name,
        'note': note,
        'ordering': ordering,
        'is_active': true,
      },
      applyChange: () async {
        await _db.into(_db.laundryMachineRows).insertOnConflictUpdate(
              LaundryMachineRow(
                id: id,
                name: name,
                note: note,
                isActive: true,
                ordering: ordering,
                updatedAt: now,
              ),
            );
      },
    );
    return id;
  }

  Future<void> updateMachine({
    required String id,
    required String name,
    String? note,
    required bool isActive,
  }) async {
    final now = DateTime.now().toUtc();
    final previous = await (_db.select(_db.laundryMachineRows)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (previous == null) return;

    await OutboxHelper.update(
      db: _db,
      entity: 'laundry_machines',
      rowId: id,
      payload: {
        'id': id,
        'name': name,
        'note': note,
        'is_active': isActive,
      },
      queryExisting: () async => previous.toJson(),
      applyChange: () async {
        await _db.into(_db.laundryMachineRows).insertOnConflictUpdate(
              previous.copyWith(
                name: name,
                note: Value(note),
                isActive: isActive,
                updatedAt: now,
              ),
            );
      },
    );
  }

  Future<void> deleteMachine(String id) async {
    final previous = await (_db.select(_db.laundryMachineRows)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (previous == null) return;

    await OutboxHelper.delete(
      db: _db,
      entity: 'laundry_machines',
      rowId: id,
      queryExisting: () async => previous.toJson(),
      applyChange: () async {
        await (_db.delete(_db.laundryMachineRows)..where((t) => t.id.equals(id)))
            .go();
      },
    );
  }

  // --- Faixas de horário (outbox) --------------------------------------------

  Future<String> createTimeSlot({
    required int startsAtMinutes,
    int? endsAtMinutes,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    final existing = await _db.select(_db.laundryTimeSlotRows).get();
    final ordering =
        existing.fold<int>(0, (max, s) => s.ordering > max ? s.ordering : max) + 1;

    await OutboxHelper.insert(
      db: _db,
      entity: 'laundry_time_slots',
      rowId: id,
      payload: {
        'id': id,
        'starts_at': _minutesToTime(startsAtMinutes),
        'ends_at': endsAtMinutes != null ? _minutesToTime(endsAtMinutes) : null,
        'ordering': ordering,
        'is_active': true,
      },
      applyChange: () async {
        await _db.into(_db.laundryTimeSlotRows).insertOnConflictUpdate(
              LaundryTimeSlotRow(
                id: id,
                startsAtMinutes: startsAtMinutes,
                endsAtMinutes: endsAtMinutes,
                isActive: true,
                ordering: ordering,
                updatedAt: now,
              ),
            );
      },
    );
    return id;
  }

  Future<void> deleteTimeSlot(String id) async {
    final previous = await (_db.select(_db.laundryTimeSlotRows)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (previous == null) return;

    await OutboxHelper.delete(
      db: _db,
      entity: 'laundry_time_slots',
      rowId: id,
      queryExisting: () async => previous.toJson(),
      applyChange: () async {
        await (_db.delete(_db.laundryTimeSlotRows)
              ..where((t) => t.id.equals(id)))
            .go();
      },
    );
  }

  // --- Intervalos (outbox) ----------------------------------------------------

  /// Marca uma célula como intervalo, para **todo** aquele dia da semana.
  Future<String> blockSlot({
    required String machineId,
    required String timeSlotId,
    required int weekday,
    String? reason,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();

    await OutboxHelper.insert(
      db: _db,
      entity: 'laundry_blocks',
      rowId: id,
      payload: {
        'id': id,
        'machine_id': machineId,
        'time_slot_id': timeSlotId,
        'weekday': weekday,
        'reason': reason,
      },
      applyChange: () async {
        await _db.into(_db.laundryBlockRows).insertOnConflictUpdate(
              LaundryBlockRow(
                id: id,
                machineId: machineId,
                timeSlotId: timeSlotId,
                weekday: weekday,
                reason: reason,
                updatedAt: now,
              ),
            );
      },
    );
    return id;
  }

  /// Libera uma célula que estava marcada como intervalo.
  Future<void> unblockSlot(String blockId) async {
    final previous = await (_db.select(_db.laundryBlockRows)
          ..where((t) => t.id.equals(blockId)))
        .getSingleOrNull();
    if (previous == null) return;

    await OutboxHelper.delete(
      db: _db,
      entity: 'laundry_blocks',
      rowId: blockId,
      queryExisting: () async => previous.toJson(),
      applyChange: () async {
        await (_db.delete(_db.laundryBlockRows)
              ..where((t) => t.id.equals(blockId)))
            .go();
      },
    );
  }

  /// Minutos desde a meia-noite para "HH:MM:SS", que é o formato do tipo
  /// `time` do Postgres.
  static String _minutesToTime(int minutes) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(minutes ~/ 60)}:${two(minutes % 60)}:00';
  }
}
