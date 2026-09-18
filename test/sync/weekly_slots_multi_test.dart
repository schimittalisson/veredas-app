import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/repositories/agenda_repository.dart';

import '../helpers/test_helpers.dart';

// Criar o mesmo horário em vários dias da semana de uma vez.
//
// O que importa aqui é a **forma** do resultado: N linhas independentes, e não
// uma linha com uma lista de dias. É isso que permite depois mudar só a sexta
// sem virar caso especial no modelo — e é o que os testes fixam.

void main() {
  late AppDatabase db;
  late AgendaRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = AgendaRepository(db);
  });
  tearDown(() => db.close());

  Future<List<WeeklySlotRow>> slots() =>
      (db.select(db.weeklySlotRows)..orderBy([(t) => OrderingTerm(expression: t.weekday)]))
          .get();

  test('cria uma linha por dia marcado', () async {
    final ids = await repo.createWeeklySlotsForWeekdays(
      weekdays: {1, 3, 5},
      startsAtMinutes: 6 * 60,
      endsAtMinutes: 7 * 60,
      title: 'Meditação na palavra',
    );

    expect(ids, hasLength(3));
    expect(ids.toSet(), hasLength(3), reason: 'ids precisam ser distintos');

    final rows = await slots();
    expect(rows.map((r) => r.weekday), [1, 3, 5]);
    expect(rows.every((r) => r.title == 'Meditação na palavra'), true);
    expect(rows.every((r) => r.startsAtMinutes == 360), true);
    expect(rows.every((r) => r.endsAtMinutes == 420), true);
  });

  test('a semana toda vira sete linhas', () async {
    await repo.createWeeklySlotsForWeekdays(
      weekdays: {1, 2, 3, 4, 5, 6, 7},
      startsAtMinutes: 6 * 60,
      title: 'Meditação na palavra',
    );

    final rows = await slots();
    expect(rows.map((r) => r.weekday), [1, 2, 3, 4, 5, 6, 7]);
  });

  test('cada dia gera sua própria entrada na outbox', () async {
    await repo.createWeeklySlotsForWeekdays(
      weekdays: {2, 4},
      startsAtMinutes: 19 * 60,
      title: 'Culto',
    );

    final outbox = await db.select(db.outboxEntries).get();
    final weeklySlotOps =
        outbox.where((o) => o.entity == 'weekly_slots').toList();
    expect(weeklySlotOps, hasLength(2));

    // O payload que vai ao servidor precisa levar o dia certo em cada uma —
    // enfileirar duas vezes o mesmo dia passaria despercebido no cache local,
    // onde os ids são diferentes, e só quebraria no servidor.
    final weekdays = weeklySlotOps
        .map((o) => (jsonDecode(o.payload) as Map<String, dynamic>)['weekday'])
        .toList();
    expect(weekdays..sort(), [2, 4]);
  });

  test('um dia só se comporta como o create de sempre', () async {
    final ids = await repo.createWeeklySlotsForWeekdays(
      weekdays: {6},
      startsAtMinutes: 8 * 60,
      title: 'Limpeza',
    );

    expect(ids, hasLength(1));
    final rows = await slots();
    expect(rows.single.weekday, 6);
  });

  test('editar um dos dias não toca nos irmãos', () async {
    final ids = await repo.createWeeklySlotsForWeekdays(
      weekdays: {1, 3},
      startsAtMinutes: 6 * 60,
      title: 'Meditação na palavra',
    );

    await repo.updateWeeklySlot(
      id: ids.first,
      weekday: 1,
      startsAtMinutes: 5 * 60,
      title: 'Meditação na palavra',
    );

    final rows = await slots();
    final segunda = rows.firstWhere((r) => r.weekday == 1);
    final quarta = rows.firstWhere((r) => r.weekday == 3);
    expect(segunda.startsAtMinutes, 300);
    expect(quarta.startsAtMinutes, 360, reason: 'a quarta não deve mudar');
  });
}
