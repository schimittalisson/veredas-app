import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/error/error_mapper.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/remote/laundry_service.dart';
import 'package:veredas/data/repositories/laundry_repository.dart';
import 'package:veredas/data/sync/sync_entity.dart';
import 'package:veredas/data/sync/sync_service.dart';
import 'package:veredas/providers/laundry_providers.dart';

import '../helpers/test_helpers.dart';

// Lavanderia: a planilha de uso das máquinas, agora reservável no app.
//
// O que estes testes protegem, em ordem de importância:
//
// 1. O conflito de reserva simultânea chega ao app como `conflict`, que é o
//    que dispara a mensagem "atualize a planilha". Se esse mapeamento quebrar,
//    duas pessoas acham que reservaram o mesmo horário.
// 2. Cancelamento se propaga. A reserva cancelada precisa sumir da grade dos
//    outros aparelhos, senão o horário fica travado para sempre.
// 3. Remoção de cadastro se propaga (máquina, horário, intervalo).

/// Serviço de lavanderia falso: registra as chamadas e devolve o erro pedido.
class _FakeLaundryService implements LaundryService {
  final List<String> calls = [];
  dynamic reserveError;
  dynamic cancelError;

  @override
  Future<String> reserve({
    required String machineId,
    required String timeSlotId,
    required DateTime onDate,
  }) async {
    calls.add('reserve:$machineId:$timeSlotId:${onDate.toIso8601String()}');
    if (reserveError != null) {
      final e = reserveError;
      reserveError = null;
      throw e;
    }
    return 'r1';
  }

  @override
  Future<void> cancel(String reservationId) async {
    calls.add('cancel:$reservationId');
    if (cancelError != null) {
      final e = cancelError;
      cancelError = null;
      throw e;
    }
  }
}

Map<String, dynamic> machineJson({
  String id = 'm1',
  String name = 'Máquina 1',
  String? note = 'grande',
  bool isActive = true,
  DateTime? updatedAt,
}) =>
    {
      'id': id,
      'name': name,
      'note': note,
      'is_active': isActive,
      'ordering': 1,
      'updated_at': (updatedAt ?? DateTime.utc(2026, 9, 1)).toIso8601String(),
    };

Map<String, dynamic> timeSlotJson({
  String id = 't1',
  String startsAt = '05:30:00',
  String? endsAt = '07:00:00',
  DateTime? updatedAt,
}) =>
    {
      'id': id,
      'starts_at': startsAt,
      'ends_at': endsAt,
      'is_active': true,
      'ordering': 1,
      'updated_at': (updatedAt ?? DateTime.utc(2026, 9, 1)).toIso8601String(),
    };

Map<String, dynamic> blockJson({
  String id = 'b1',
  String machineId = 'm1',
  String timeSlotId = 't1',
  int weekday = 2,
  DateTime? updatedAt,
}) =>
    {
      'id': id,
      'machine_id': machineId,
      'time_slot_id': timeSlotId,
      'weekday': weekday,
      'reason': null,
      'updated_at': (updatedAt ?? DateTime.utc(2026, 9, 1)).toIso8601String(),
    };

Map<String, dynamic> reservationJson({
  String id = 'r1',
  String machineId = 'm1',
  String timeSlotId = 't1',
  String onDate = '2026-09-21',
  String userId = 'u1',
  String userName = 'Julia Fernandes',
  DateTime? updatedAt,
  DateTime? deletedAt,
}) =>
    {
      'id': id,
      'machine_id': machineId,
      'time_slot_id': timeSlotId,
      'on_date': onDate,
      'user_id': userId,
      'user_name': userName,
      'updated_at': (updatedAt ?? DateTime.utc(2026, 9, 18)).toIso8601String(),
      if (deletedAt != null) 'deleted_at': deletedAt.toIso8601String(),
    };

void main() {
  late AppDatabase db;
  late FakeRemoteSource remote;
  late SyncService sync;
  late _FakeLaundryService service;
  late LaundryRepository repo;

  setUp(() {
    db = createTestDatabase();
    remote = FakeRemoteSource();
    sync = SyncService(db: db, remote: remote);
    service = _FakeLaundryService();
    repo = LaundryRepository(db, service);
  });
  tearDown(() => db.close());

  group('conversores de sync', () {
    test('a máquina chega ao cache com nome e observação', () async {
      remote.fetchData['laundry_machines'] = [machineJson()];
      await sync.pull(syncEntityByName('laundry_machines')!);

      final row = (await db.select(db.laundryMachineRows).get()).single;
      expect(row.name, 'Máquina 1');
      expect(row.note, 'grande');
    });

    test('a faixa de horário vira minutos desde a meia-noite', () async {
      remote.fetchData['laundry_time_slots'] = [timeSlotJson()];
      await sync.pull(syncEntityByName('laundry_time_slots')!);

      final row = (await db.select(db.laundryTimeSlotRows).get()).single;
      // 05:30 = 330; 07:00 = 420.
      expect(row.startsAtMinutes, 330);
      expect(row.endsAtMinutes, 420);
    });

    test('a reserva chega com o nome de quem reservou', () async {
      remote.fetchData['laundry_grid'] = [reservationJson()];
      await sync.pull(syncEntityByName('laundry_reservations')!);

      final row = (await db.select(db.laundryReservationRows).get()).single;
      expect(row.userName, 'Julia Fernandes');
      expect(row.onDate, DateTime.parse('2026-09-21'));
    });
  });

  group('propagação de remoções', () {
    test('máquina apagada no servidor some do cache', () async {
      remote.fetchData['laundry_machines'] = [
        machineJson(id: 'm1'),
        machineJson(id: 'm2', name: 'Máquina 2'),
      ];
      await sync.pull(syncEntityByName('laundry_machines')!);
      expect(await db.laundryMachineRows.count().getSingle(), 2);

      // A policy de leitura filtra `deleted_at`, então uma máquina removida
      // simplesmente deixa de voltar. Só a substituição total percebe.
      remote.fetchData['laundry_machines'] = [machineJson(id: 'm1')];
      await sync.pull(syncEntityByName('laundry_machines')!);

      final rows = await db.select(db.laundryMachineRows).get();
      expect(rows.map((r) => r.id), ['m1']);
    });

    test('intervalo liberado pelo admin some do cache', () async {
      remote.fetchData['laundry_blocks'] = [blockJson()];
      await sync.pull(syncEntityByName('laundry_blocks')!);
      expect(await db.laundryBlockRows.count().getSingle(), 1);

      remote.fetchData['laundry_blocks'] = [];
      await sync.pull(syncEntityByName('laundry_blocks')!);
      expect(await db.laundryBlockRows.count().getSingle(), 0);
    });

    test('reserva cancelada some do cache', () async {
      remote.fetchData['laundry_grid'] = [reservationJson()];
      await sync.pull(syncEntityByName('laundry_reservations')!);
      expect(await db.laundryReservationRows.count().getSingle(), 1);

      // Cancelar é soft delete. É por isso que a policy dessa tabela deixa as
      // canceladas visíveis: sem a linha voltar com `deleted_at`, o pull
      // incremental nunca saberia, e o horário ficaria travado para sempre.
      remote.fetchData['laundry_grid'] = [
        reservationJson(
          updatedAt: DateTime.utc(2026, 9, 19),
          deletedAt: DateTime.utc(2026, 9, 19),
        ),
      ];
      await sync.pull(syncEntityByName('laundry_reservations')!);

      expect(await db.laundryReservationRows.count().getSingle(), 0);
    });
  });

  group('reserva', () {
    test('delega ao serviço com máquina, faixa e data', () async {
      await repo.reserve(
        machineId: 'm1',
        timeSlotId: 't1',
        onDate: DateTime(2026, 9, 21),
      );

      expect(service.calls.single, startsWith('reserve:m1:t1:'));
    });

    test('não escreve no cache antes de o servidor confirmar', () async {
      await repo.reserve(
        machineId: 'm1',
        timeSlotId: 't1',
        onDate: DateTime(2026, 9, 21),
      );

      // Pintar a célula como "sua" antes da confirmação obrigaria a despintar
      // quando outra pessoa tivesse levado o horário — a confusão que esta
      // feature existe para evitar. Quem traz a reserva é o pull seguinte.
      expect(await db.laundryReservationRows.count().getSingle(), 0);
      // E também não entra na outbox: reservar offline não significa nada.
      expect(await db.outboxEntries.count().getSingle(), 0);
    });

    test('o conflito do servidor sobe como AppException', () async {
      service.reserveError = const AppException(AppErrorCode.conflict);

      await expectLater(
        repo.reserve(
          machineId: 'm1',
          timeSlotId: 't1',
          onDate: DateTime(2026, 9, 21),
        ),
        throwsA(predicate<AppException>((e) => e.code == AppErrorCode.conflict)),
      );
    });
  });

  group('cadastro pelo admin', () {
    test('criar máquina entra na outbox e aparece na hora', () async {
      final id = await repo.createMachine(name: 'Máquina 4', note: 'nova');

      final row = (await db.select(db.laundryMachineRows).get()).single;
      expect(row.id, id);
      expect(row.name, 'Máquina 4');
      // Cadastro é administração comum: otimista e enfileirado, ao contrário
      // da reserva.
      expect(await db.outboxEntries.count().getSingle(), 1);
    });

    test('marcar e liberar intervalo', () async {
      final id = await repo.blockSlot(
        machineId: 'm1',
        timeSlotId: 't1',
        weekday: 2,
      );
      expect(await db.laundryBlockRows.count().getSingle(), 1);

      await repo.unblockSlot(id);
      expect(await db.laundryBlockRows.count().getSingle(), 0);
    });
  });

  group('mapeamento de erro das RPCs', () {
    test('LAUNDRY_SLOT_BLOCKED vira laundrySlotBlocked', () {
      final e = makePostgrestException(
        message: 'LAUNDRY_SLOT_BLOCKED',
        code: 'P0001',
      );
      expect(mapError(e).code, AppErrorCode.laundrySlotBlocked);
    });

    test('a violação de unicidade vira conflict', () {
      // É o caminho da reserva simultânea: o índice único recusa a segunda
      // gravação, e é esse código que vira "horário já reservado".
      final e = makePostgrestException(message: 'duplicate key', code: '23505');
      expect(mapError(e).code, AppErrorCode.conflict);
    });
  });

  group('chaves da grade', () {
    test('a semana começa na segunda', () {
      // 2026-09-18 é uma sexta-feira.
      final monday = LaundryWeekNotifier.mondayOf(DateTime(2026, 9, 18));
      expect(monday, DateTime(2026, 9, 14));
      expect(monday.weekday, DateTime.monday);
    });

    test('a segunda-feira é o seu próprio início de semana', () {
      final monday = LaundryWeekNotifier.mondayOf(DateTime(2026, 9, 14));
      expect(monday, DateTime(2026, 9, 14));
    });

    test('a chave da reserva ignora a hora da data', () {
      final a = reservationKey('m1', 't1', DateTime(2026, 9, 21));
      final b = reservationKey('m1', 't1', DateTime(2026, 9, 21, 23, 59));
      expect(a, b);
    });
  });
}
