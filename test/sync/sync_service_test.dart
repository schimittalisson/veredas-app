import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/sync/sync_entity.dart';
import 'package:veredas/data/sync/sync_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late AppDatabase db;
  late FakeRemoteSource remote;
  late SyncService syncService;

  setUp(() {
    db = createTestDatabase();
    remote = FakeRemoteSource();
    syncService = SyncService(db: db, remote: remote);
  });
  tearDown(() => db.close());

  group('SyncService.pull — incremental', () {
    test('insere linhas novas no cache', () async {
      remote.fetchData['announcements'] = [
        makeAnnouncementJson(
          id: 'a1',
          title: 'Aviso de hoje',
          body: 'Reunião cancelada',
          updatedAt: DateTime.utc(2026, 8, 4, 10, 0),
        ),
      ];

      await syncService.pull(syncEntityByName('announcements')!);

      final rows = await db.select(db.announcementRows).get();
      expect(rows.length, 1);
      expect(rows.first.id, 'a1');
      expect(rows.first.title, 'Aviso de hoje');
      expect(rows.first.body, 'Reunião cancelada');
    });

    test('atualiza linhas existentes (upsert, não duplica)', () async {
      // Primeiro pull: insere.
      remote.fetchData['announcements'] = [
        makeAnnouncementJson(
          id: 'a1',
          body: 'Original',
          updatedAt: DateTime.utc(2026, 8, 1, 10, 0),
        ),
      ];
      await syncService.pull(syncEntityByName('announcements')!);

      // Segundo pull: mesma linha, body atualizado.
      remote.fetchData['announcements'] = [
        makeAnnouncementJson(
          id: 'a1',
          body: 'Editado',
          updatedAt: DateTime.utc(2026, 8, 2, 10, 0),
        ),
      ];
      await syncService.pull(syncEntityByName('announcements')!);

      final rows = await db.select(db.announcementRows).get();
      expect(rows.length, 1, reason: 'upsert não duplica');
      expect(rows.first.body, 'Editado');
    });

    test('remove linhas com deleted_at != null (soft delete propaga)',
        () async {
      // Primeiro pull: insere.
      remote.fetchData['announcements'] = [
        makeAnnouncementJson(
          id: 'a1',
          updatedAt: DateTime.utc(2026, 8, 1, 10, 0),
        ),
      ];
      await syncService.pull(syncEntityByName('announcements')!);
      expect(await db.announcementRows.count().getSingle(), 1);

      // Segundo pull: a mesma linha chega com deleted_at.
      remote.fetchData['announcements'] = [
        makeAnnouncementJson(
          id: 'a1',
          updatedAt: DateTime.utc(2026, 8, 2, 10, 0),
          deletedAt: DateTime.utc(2026, 8, 2, 9, 0),
        ),
      ];
      await syncService.pull(syncEntityByName('announcements')!);

      // A linha é removida fisicamente do cache — não fica com deleted_at.
      expect(await db.announcementRows.count().getSingle(), 0);
    });

    test('é idempotente: rodar duas vezes com os mesmos dados não duplica',
        () async {
      final data = [
        makeAnnouncementJson(id: 'a1', updatedAt: DateTime.utc(2026, 8, 1)),
        makeAnnouncementJson(id: 'a2', updatedAt: DateTime.utc(2026, 8, 2)),
      ];

      remote.fetchData['announcements'] = data;
      await syncService.pull(syncEntityByName('announcements')!);

      // Segunda vez: mesmos dados (simula reprocessamento da janela de 2min).
      remote.fetchData['announcements'] = data;
      await syncService.pull(syncEntityByName('announcements')!);

      final rows = await db.select(db.announcementRows).get();
      expect(rows.length, 2);
      expect(rows.map((r) => r.id).toSet(), {'a1', 'a2'});
    });

    test('atualiza sync_state com max(updated_at) recebido', () async {
      remote.fetchData['announcements'] = [
        makeAnnouncementJson(id: 'a1', updatedAt: DateTime.utc(2026, 8, 1)),
        makeAnnouncementJson(id: 'a2', updatedAt: DateTime.utc(2026, 8, 3)),
        makeAnnouncementJson(id: 'a3', updatedAt: DateTime.utc(2026, 8, 2)),
      ];

      await syncService.pull(syncEntityByName('announcements')!);

      final state = await (db.select(db.syncStates)
            ..where((t) => t.entity.equals('announcements')))
          .getSingle();
      // O drift devolve DateTime em hora local; compara em UTC para ser
      // independente de fuso.
      expect(state.lastSyncedAt!.toUtc(), DateTime.utc(2026, 8, 3));
      expect(state.lastError, isNull);
    });

    test('converte tipos: time → minutos, text[] → List<String>, date → DateTime',
        () async {
      remote.fetchData['weekly_slots'] = [
        {
          'id': 'w1',
          'weekday': 1,
          'starts_at': '06:00:00',
          'ends_at': '07:30:00',
          'title': 'Oração matinal',
          'location': 'Capela',
          'category': 'oracao',
          'notes': null,
          'is_active': true,
          'ordering': 0,
          'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        },
      ];
      remote.fetchData['scale_types'] = [
        {
          'id': 'st1',
          'slug': 'servir-ao-todo',
          'name': 'Servir ao Todo',
          'description': null,
          'icon': 'cleaning_services',
          'cadence': 'weekly',
          'slots': ['06:00-07:00', 'Cozinha, área comum', ''],
          'ordering': 0,
          'is_active': true,
          'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        },
      ];

      await syncService.pull(syncEntityByName('weekly_slots')!);
      await syncService.pull(syncEntityByName('scale_types')!);

      final slot = await db.select(db.weeklySlotRows).getSingle();
      expect(slot.weekday, 1);
      expect(slot.startsAtMinutes, 360, reason: '06:00 = 360 min');
      expect(slot.endsAtMinutes, 450, reason: '07:30 = 450 min');

      final scaleType = await db.select(db.scaleTypeRows).getSingle();
      expect(scaleType.slots, ['06:00-07:00', 'Cozinha, área comum', '']);
    });
  });

  group('SyncService.pull — fullReplace', () {
    test('substitui todo o cache a cada sync', () async {
      // Primeiro sync: 2 responsáveis.
      remote.fetchData['scale_managers'] = [
        makeScaleManagerJson(scaleTypeId: 'st1', userId: 'u1'),
        makeScaleManagerJson(scaleTypeId: 'st1', userId: 'u2'),
      ];
      await syncService.pull(syncEntityByName('scale_managers')!);
      expect(await db.scaleManagerRows.count().getSingle(), 2);

      // Segundo sync: u2 foi removido no servidor (DELETE físico).
      // O incremental não detectaria, mas fullReplace sim.
      remote.fetchData['scale_managers'] = [
        makeScaleManagerJson(scaleTypeId: 'st1', userId: 'u1'),
      ];
      await syncService.pull(syncEntityByName('scale_managers')!);

      expect(await db.scaleManagerRows.count().getSingle(), 1);
      final row = await db.select(db.scaleManagerRows).getSingle();
      expect(row.userId, 'u1');
    });

    test('prayer_feed (view) usa fullReplace — post apagado desaparece',
        () async {
      remote.fetchData['prayer_feed'] = [
        {
          'id': 'pf1',
          'author_id': 'u1',
          'title': 'Oração pela cura',
          'body': 'Peço oração pela saúde',
          'is_anonymous': false,
          'answered_at': null,
          'answer_note': null,
          'author_name': 'Maria',
          'author_avatar_url': null,
          'praying_count': 3,
          'comment_count': 1,
          'is_praying': false,
          'created_at': DateTime.utc(2026, 8, 1).toIso8601String(),
          'updated_at': DateTime.utc(2026, 8, 1).toIso8601String(),
        },
      ];
      await syncService.pull(syncEntityByName('prayer_feed')!);
      expect(await db.prayerFeedRows.count().getSingle(), 1);

      // Segundo sync: a view não retorna o post (foi soft-deleted em
      // prayer_posts, a view filtra deleted_at is null).
      remote.fetchData['prayer_feed'] = [];
      await syncService.pull(syncEntityByName('prayer_feed')!);

      expect(await db.prayerFeedRows.count().getSingle(), 0);
    });
  });

  group('SyncService.pullAll', () {
    test('sincroniza múltiplas entidades em ordem', () async {
      remote.fetchData['profiles'] = [
        makeProfileJson(id: 'p1', updatedAt: DateTime.utc(2026, 1, 1)),
      ];
      remote.fetchData['announcements'] = [
        makeAnnouncementJson(id: 'a1', updatedAt: DateTime.utc(2026, 1, 1)),
      ];

      await syncService.pullAll();

      expect(await db.profileRows.count().getSingle(), 1);
      expect(await db.announcementRows.count().getSingle(), 1);
    });

    test('para no primeiro erro e não sincroniza as seguintes', () async {
      remote.fetchErrors['profiles'] = makeSocketException();
      remote.fetchData['announcements'] = [
        makeAnnouncementJson(id: 'a1', updatedAt: DateTime.utc(2026, 1, 1)),
      ];

      await expectLater(
        syncService.pullAll(),
        throwsA(isA<AppException>()),
      );

      // announcements não foi sincronizada porque profiles falhou primeiro.
      expect(await db.announcementRows.count().getSingle(), 0);
    });

    test('grava lastError no sync_state quando o pull falha', () async {
      remote.fetchErrors['announcements'] = makeSocketException();

      await expectLater(
        syncService.pull(syncEntityByName('announcements')!),
        throwsA(predicate<AppException>((e) =>
            e.code == AppErrorCode.noConnection)),
      );

      final state = await (db.select(db.syncStates)
            ..where((t) => t.entity.equals('announcements')))
          .getSingle();
      expect(state.lastError, AppErrorCode.noConnection.name);
    });
  });

  group('SyncService — janela de segurança', () {
    test('o filtro updated_at usa lastSyncedAt - 2min', () async {
      // Primeiro sync: estabelece lastSyncedAt.
      remote.fetchData['announcements'] = [
        makeAnnouncementJson(
          id: 'a1',
          updatedAt: DateTime.utc(2026, 8, 1, 10, 0),
        ),
      ];
      await syncService.pull(syncEntityByName('announcements')!);

      // Segundo sync: verifica o gtValue passado ao remote.
      remote.fetchData['announcements'] = [];
      await syncService.pull(syncEntityByName('announcements')!);

      final fetchCall = remote.calls
          .where((c) => c.method == 'fetch' && c.table == 'announcements')
          .last;
      final gtValue = fetchCall.extra!['gtValue'] as String;
      // lastSyncedAt (2026-08-01T10:00:00) - 2min = 2026-08-01T09:58:00
      final cutoff = DateTime.parse(gtValue);
      expect(cutoff, DateTime.utc(2026, 8, 1, 9, 58));
    });
  });
}
