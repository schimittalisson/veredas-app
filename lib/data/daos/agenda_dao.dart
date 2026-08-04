import 'package:drift/drift.dart';

import 'package:veredas/data/local/app_database.dart';

/// DAO da tela Agenda: eventos e cronograma semanal.
class AgendaDao {
  AgendaDao(this.db);

  final AppDatabase db;

  // --- Events (eventos pontuais) -------------------------------------------

  /// Eventos a partir de uma data (para o calendário/lista do dia).
  Stream<List<EventRow>> watchEventsFrom(DateTime start) {
    return (db.select(db.eventRows)
          ..where((t) => t.startsAt.isBiggerOrEqualValue(start))
          ..orderBy([(t) => OrderingTerm.asc(t.startsAt)]))
        .watch();
  }

  /// Todos os eventos (para marcadores do calendário).
  Stream<List<EventRow>> watchAllEvents() {
    return (db.select(db.eventRows)
          ..orderBy([(t) => OrderingTerm.asc(t.startsAt)]))
        .watch();
  }

  Future<EventRow?> getEvent(String id) {
    return (db.select(db.eventRows)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertEvent(EventRow row) {
    return db.into(db.eventRows).insertOnConflictUpdate(row);
  }

  Future<void> removeEvent(String id) {
    return (db.delete(db.eventRows)..where((t) => t.id.equals(id))).go();
  }

  // --- Weekly slots (cronograma semanal fixo) ------------------------------

  /// Slots do cronograma, ordenados por dia e horário.
  Stream<List<WeeklySlotRow>> watchWeeklySlots() {
    return (db.select(db.weeklySlotRows)
          ..orderBy([
            (t) => OrderingTerm.asc(t.weekday),
            (t) => OrderingTerm.asc(t.startsAtMinutes),
          ]))
        .watch();
  }

  /// Slots de um dia específico (1=segunda ... 7=domingo).
  Stream<List<WeeklySlotRow>> watchWeeklySlotsByDay(int weekday) {
    return (db.select(db.weeklySlotRows)
          ..where((t) => t.weekday.equals(weekday))
          ..orderBy([(t) => OrderingTerm.asc(t.startsAtMinutes)]))
        .watch();
  }

  Future<WeeklySlotRow?> getWeeklySlot(String id) {
    return (db.select(db.weeklySlotRows)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertWeeklySlot(WeeklySlotRow row) {
    return db.into(db.weeklySlotRows).insertOnConflictUpdate(row);
  }

  Future<void> removeWeeklySlot(String id) {
    return (db.delete(db.weeklySlotRows)..where((t) => t.id.equals(id))).go();
  }
}
