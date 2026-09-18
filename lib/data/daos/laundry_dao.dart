import 'package:drift/drift.dart';

import 'package:veredas/data/local/app_database.dart';

/// Leituras da lavanderia — streams do cache drift.
///
/// A tela monta a grade cruzando os quatro streams. Cruzar aqui, num único
/// join SQL, seria mais eficiente, mas devolveria uma linha por célula
/// preenchida e nenhuma pelas vazias — e a grade precisa desenhar as vazias,
/// que são justamente as reserváveis.
class LaundryDao {
  LaundryDao(this._db);

  final AppDatabase _db;

  /// Máquinas ativas, na ordem do cadastro (as colunas da grade).
  Stream<List<LaundryMachineRow>> watchMachines() {
    return (_db.select(_db.laundryMachineRows)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([
            (t) => OrderingTerm(expression: t.ordering),
            (t) => OrderingTerm(expression: t.name),
          ]))
        .watch();
  }

  /// Todas as máquinas, inclusive inativas — para a tela de administração.
  Stream<List<LaundryMachineRow>> watchAllMachines() {
    return (_db.select(_db.laundryMachineRows)
          ..orderBy([
            (t) => OrderingTerm(expression: t.ordering),
            (t) => OrderingTerm(expression: t.name),
          ]))
        .watch();
  }

  /// Faixas de horário ativas, em ordem cronológica (as linhas da grade).
  Stream<List<LaundryTimeSlotRow>> watchTimeSlots() {
    return (_db.select(_db.laundryTimeSlotRows)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([
            (t) => OrderingTerm(expression: t.ordering),
            (t) => OrderingTerm(expression: t.startsAtMinutes),
          ]))
        .watch();
  }

  Stream<List<LaundryTimeSlotRow>> watchAllTimeSlots() {
    return (_db.select(_db.laundryTimeSlotRows)
          ..orderBy([
            (t) => OrderingTerm(expression: t.ordering),
            (t) => OrderingTerm(expression: t.startsAtMinutes),
          ]))
        .watch();
  }

  /// Bloqueios — recorrentes por dia da semana, sem data.
  Stream<List<LaundryBlockRow>> watchBlocks() {
    return _db.select(_db.laundryBlockRows).watch();
  }

  /// Reservas de um intervalo de datas (a semana exibida).
  ///
  /// Filtrar por período em vez de trazer tudo mantém a consulta barata à
  /// medida que o histórico cresce.
  Stream<List<LaundryReservationRow>> watchReservationsBetween(
    DateTime from,
    DateTime to,
  ) {
    return (_db.select(_db.laundryReservationRows)
          ..where((t) => t.onDate.isBetweenValues(from, to)))
        .watch();
  }
}
