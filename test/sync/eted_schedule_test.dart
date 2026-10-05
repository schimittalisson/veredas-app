import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/local/tables.dart'
    show kScheduleBase, kScheduleEted;
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/data/repositories/agenda_repository.dart';
import 'package:veredas/data/sync/sync_entity.dart';
import 'package:veredas/data/sync/sync_service.dart';
import 'package:veredas/providers/agenda_providers.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';

import '../helpers/test_helpers.dart';

// O cronograma da ETED mora na mesma tabela do cronograma da base, separado
// pela coluna `schedule`. O que estes testes fixam é que a coluna atravessa
// todo o caminho — escrita, outbox, pull e migração do cache — e que quem
// edita cada grade é decidido por ela.

const _me = 'user-me';
const _other = 'user-other';

Map<String, dynamic> _slotJson({
  required String id,
  String? schedule,
  int weekday = 1,
}) =>
    {
      'id': id,
      'weekday': weekday,
      'starts_at': '08:00:00',
      'ends_at': null,
      'title': 'Aula $id',
      'location': null,
      'category': null,
      'notes': null,
      'is_active': true,
      'ordering': 0,
      'color_index': null,
      'schedule': ?schedule,
      'updated_at': '2026-10-01T12:00:00Z',
      'deleted_at': null,
    };

void main() {
  late AppDatabase db;
  late AgendaRepository repo;

  setUp(() {
    db = createTestDatabase();
    repo = AgendaRepository(db);
  });
  tearDown(() => db.close());

  group('escrita', () {
    test('horário da ETED nasce na grade da ETED e vai assim ao servidor',
        () async {
      await repo.createWeeklySlotsForWeekdays(
        schedule: kScheduleEted,
        weekdays: {1, 3},
        startsAtMinutes: 8 * 60,
        title: 'Preleção',
      );

      final rows = await db.select(db.weeklySlotRows).get();
      expect(rows.map((r) => r.schedule), everyElement(kScheduleEted));

      final payloads = (await db.select(db.outboxEntries).get())
          .map((o) => jsonDecode(o.payload) as Map<String, dynamic>);
      expect(payloads.map((p) => p['schedule']), everyElement(kScheduleEted));
    });

    test('sem dizer o cronograma, o horário é da base', () async {
      await repo.createWeeklySlot(
        weekday: 2,
        startsAtMinutes: 6 * 60,
        title: 'Meditação',
      );

      final row = await db.select(db.weeklySlotRows).getSingle();
      expect(row.schedule, kScheduleBase);
      final payload = jsonDecode(
        (await db.select(db.outboxEntries).getSingle()).payload,
      ) as Map<String, dynamic>;
      expect(payload['schedule'], kScheduleBase);
    });

    test('editar não manda o cronograma — o horário fica onde nasceu',
        () async {
      final id = await repo.createWeeklySlot(
        schedule: kScheduleEted,
        weekday: 2,
        startsAtMinutes: 6 * 60,
        title: 'Aula',
      );
      await repo.updateWeeklySlot(
        id: id,
        weekday: 3,
        startsAtMinutes: 7 * 60,
        title: 'Aula 2',
      );

      final row = await db.select(db.weeklySlotRows).getSingle();
      expect(row.schedule, kScheduleEted);
      final update = (await db.select(db.outboxEntries).get()).last;
      expect(
        (jsonDecode(update.payload) as Map<String, dynamic>)
            .containsKey('schedule'),
        isFalse,
      );
    });
  });

  group('pull', () {
    late FakeRemoteSource remote;
    late SyncService sync;

    setUp(() {
      remote = FakeRemoteSource();
      sync = SyncService(db: db, remote: remote);
    });

    test('grava o cronograma que vem do servidor', () async {
      remote.fetchData['weekly_slots'] = [
        _slotJson(id: 'b', schedule: kScheduleBase),
        _slotJson(id: 'e', schedule: kScheduleEted),
      ];
      await sync.pull(syncEntityByName('weekly_slots')!);

      final rows = {
        for (final r in await db.select(db.weeklySlotRows).get())
          r.id: r.schedule,
      };
      expect(rows, {'b': kScheduleBase, 'e': kScheduleEted});
    });

    test('servidor sem a coluna (antes da migration) dá tudo como base',
        () async {
      remote.fetchData['weekly_slots'] = [_slotJson(id: 'x')];
      await sync.pull(syncEntityByName('weekly_slots')!);

      expect(
        (await db.select(db.weeklySlotRows).getSingle()).schedule,
        kScheduleBase,
      );
    });

    test('líder removido no servidor sai do cache (fullReplace)', () async {
      remote.fetchData['schedule_managers'] = [
        {'schedule': kScheduleEted, 'user_id': _me, 'updated_at': null},
        {'schedule': kScheduleEted, 'user_id': _other, 'updated_at': null},
      ];
      await sync.pull(syncEntityByName('schedule_managers')!);
      expect(await db.select(db.scheduleManagerRows).get(), hasLength(2));

      remote.fetchData['schedule_managers'] = [
        {'schedule': kScheduleEted, 'user_id': _other, 'updated_at': null},
      ];
      await sync.pull(syncEntityByName('schedule_managers')!);

      final left = await db.select(db.scheduleManagerRows).get();
      expect(left.map((m) => m.userId), [_other]);
    });
  });

  group('quem edita cada grade', () {
    ProviderContainer build() {
      final c = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(_me),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<void> seedMe(AppRole role) => db.into(db.profileRows).insert(
          ProfileRow(
            id: _me,
            fullName: 'Eu',
            role: role,
            isApproved: true,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );

    Future<bool> canEdit(ProviderContainer c, String schedule) async {
      c.listen(canEditScheduleProvider(schedule), (_, _) {});
      await c.read(currentProfileProvider.future);
      await c.read(scheduleManagersProvider.future);
      return c.read(canEditScheduleProvider(schedule));
    }

    test('líder da ETED edita a ETED, e só ela', () async {
      await seedMe(AppRole.obreiro);
      await db.into(db.scheduleManagerRows).insert(
            const ScheduleManagerRow(schedule: kScheduleEted, userId: _me),
          );
      final c = build();

      expect(await canEdit(c, kScheduleEted), isTrue);
      expect(await canEdit(c, kScheduleBase), isFalse);
    });

    test('obreiro que não é líder não edita nenhuma', () async {
      await seedMe(AppRole.obreiro);
      await db.into(db.scheduleManagerRows).insert(
            const ScheduleManagerRow(schedule: kScheduleEted, userId: _other),
          );
      final c = build();

      expect(await canEdit(c, kScheduleEted), isFalse);
      expect(await canEdit(c, kScheduleBase), isFalse);
    });

    test('admin edita as duas sem estar na lista', () async {
      await seedMe(AppRole.admin);
      final c = build();

      expect(await canEdit(c, kScheduleEted), isTrue);
      expect(await canEdit(c, kScheduleBase), isTrue);
    });

    test('cada grade só mostra os próprios horários', () async {
      await repo.createWeeklySlot(
        weekday: 1,
        startsAtMinutes: 360,
        title: 'Da base',
      );
      await repo.createWeeklySlot(
        schedule: kScheduleEted,
        weekday: 1,
        startsAtMinutes: 480,
        title: 'Da ETED',
      );
      final c = build();
      c.listen(scheduleSlotsProvider(kScheduleEted), (_, _) {});
      await c.read(weeklySlotsProvider.future);

      List<String> titles(String schedule) => c
          .read(scheduleSlotsProvider(schedule))
          .requireValue
          .map((s) => s.title)
          .toList();

      expect(titles(kScheduleBase), ['Da base']);
      expect(titles(kScheduleEted), ['Da ETED']);
    });
  });

  group('migration v7 -> v8', () {
    test('quem já tinha o app: horários viram base e o cronograma é '
        'baixado de novo', () async {
      // O aparelho na v7: sem a coluna, sem a tabela de líderes, e com a
      // marca d'água de weekly_slots já avançada.
      await db.customStatement(
        'ALTER TABLE weekly_slot_rows DROP COLUMN schedule',
      );
      await db.customStatement('DROP TABLE schedule_manager_rows');
      await db.customStatement(
        "INSERT INTO weekly_slot_rows (id, weekday, starts_at_minutes, title, "
        "is_active, ordering, updated_at) "
        "VALUES ('s1', 1, 360, 'Meditação', 1, 0, 0)",
      );
      await db.into(db.syncStates).insert(
            SyncStatesCompanion.insert(
              entity: 'weekly_slots',
              lastSyncedAt: Value(DateTime.utc(2026, 9, 1)),
            ),
          );
      await db.into(db.syncStates).insert(
            SyncStatesCompanion.insert(
              entity: 'events',
              lastSyncedAt: Value(DateTime.utc(2026, 9, 1)),
            ),
          );

      await db.migration.onUpgrade(Migrator(db), 7, 8);

      expect(
        (await db.select(db.weeklySlotRows).getSingle()).schedule,
        kScheduleBase,
      );
      // Só a marca d'água do cronograma sai; as outras continuam.
      final states = await db.select(db.syncStates).get();
      expect(states.map((s) => s.entity), ['events']);
      // A tabela de líderes existe e recebe linhas.
      await db.into(db.scheduleManagerRows).insert(
            const ScheduleManagerRow(schedule: kScheduleEted, userId: _me),
          );
      expect(await db.select(db.scheduleManagerRows).get(), hasLength(1));
    });
  });
}
