import 'dart:convert';

// `count()` vem do drift; o `hide` evita a colisão com os matchers do teste.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/daos/scales_dao.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/repositories/scales_repository.dart';
import 'package:veredas/data/sync/outbox_worker.dart';
import 'package:veredas/data/sync/sync_entity.dart';
import 'package:veredas/providers/scales_providers.dart';

import '../helpers/test_helpers.dart';

/// Uma atribuição como o PostgREST a devolve.
///
/// `memberIds`/`memberNames` opcionais de propósito: omiti-los simula o
/// servidor **antes** da migration da equipe, que é o estado de qualquer
/// ambiente onde ela ainda não foi aplicada.
Map<String, dynamic> makeAssignmentJson({
  String id = 'sa1',
  String scaleTypeId = 'st1',
  DateTime? startsOn,
  String? assigneeId,
  String? assigneeName,
  List<String>? memberIds,
  List<String>? memberNames,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  return {
    'id': id,
    'scale_type_id': scaleTypeId,
    'starts_on': (startsOn ?? DateTime.utc(2026, 9, 21)).toIso8601String(),
    'ends_on': null,
    'slot': null,
    'task': null,
    'assignee_id': assigneeId,
    'assignee_name': assigneeName,
    'member_ids': ?memberIds,
    'member_names': ?memberNames,
    'notes': null,
    'created_by': null,
    'updated_at': (updatedAt ?? DateTime.utc(2026, 9, 1)).toIso8601String(),
    if (deletedAt != null) 'deleted_at': deletedAt.toIso8601String(),
  };
}

void main() {
  late AppDatabase db;
  late FakeRemoteSource remote;
  late ScalesRepository repo;
  late ScalesDao dao;

  setUp(() {
    db = createTestDatabase();
    remote = FakeRemoteSource();
    repo = ScalesRepository(db);
    dao = ScalesDao(db);
  });
  tearDown(() => db.close());

  final entity = syncEntityByName('scale_assignments')!;

  group('pull', () {
    test('a equipe chega inteira ao cache', () async {
      await entity.upsert(
        db,
        makeAssignmentJson(
          memberIds: ['u1', 'u2', 'u3'],
          memberNames: ['Visitante'],
          assigneeId: 'u1',
        ),
      );

      final row = (await dao.getAssignment('sa1'))!;
      expect(row.memberIds, ['u1', 'u2', 'u3']);
      expect(row.memberNames, ['Visitante']);
      // `assignee_id` passou a significar "responsável geral".
      expect(row.assigneeId, 'u1');
    });

    test('linha de servidor sem as colunas de equipe não quebra o pull',
        () async {
      // Cenário real: a migration da equipe ainda não foi aplicada no
      // Supabase, mas o app novo já está instalado. Se isto lançasse, o
      // SyncService pararia no primeiro erro e a tela ficaria com o banner
      // vermelho permanente.
      await entity.upsert(db, makeAssignmentJson(assigneeName: 'Fulano'));

      final row = (await dao.getAssignment('sa1'))!;
      expect(row.memberIds, isEmpty);
      expect(row.memberNames, isEmpty);
      expect(row.assigneeName, 'Fulano');
    });
  });

  group('escrita pela outbox', () {
    test('criar com equipe manda member_ids e já aparece no cache', () async {
      final id = await repo.createAssignment(
        scaleTypeId: 'st1',
        startsOn: DateTime(2026, 9, 21),
        memberIds: ['u1', 'u2', 'u3', 'u4'],
        assigneeId: 'u1',
      );

      final row = (await dao.getAssignment(id))!;
      expect(row.memberIds, ['u1', 'u2', 'u3', 'u4']);

      final entry = await db.select(db.outboxEntries).getSingle();
      expect(entry.entity, 'scale_assignments');
      expect(entry.op, 'insert');
      final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
      expect(payload['member_ids'], ['u1', 'u2', 'u3', 'u4']);
      expect(payload['assignee_id'], 'u1');
    });

    test('editar substitui a equipe inteira e deixa tirar o responsável',
        () async {
      final id = await repo.createAssignment(
        scaleTypeId: 'st1',
        startsOn: DateTime(2026, 9, 21),
        memberIds: ['u1', 'u2'],
        assigneeId: 'u1',
      );

      await repo.updateAssignment(
        id: id,
        scaleTypeId: 'st1',
        startsOn: DateTime(2026, 9, 21),
        memberIds: ['u3'],
        memberNames: ['Visitante'],
      );

      final row = (await dao.getAssignment(id))!;
      expect(row.memberIds, ['u3']);
      expect(row.memberNames, ['Visitante']);
      // Responsável geral em branco é um valor válido, não "não mexeu".
      expect(row.assigneeId, isNull);
    });

    test('403 do RLS devolve a equipe anterior ao cache', () async {
      // O rollback reconstrói a linha a partir do snapshot drift JSON, e é
      // aí que o conversor de List<String> tem de sobreviver ao round-trip:
      // se ele falhasse, a escala voltaria sem a equipe — pior do que não
      // voltar, porque parece salva.
      final id = await repo.createAssignment(
        scaleTypeId: 'st1',
        startsOn: DateTime(2026, 9, 21),
        memberIds: ['u1', 'u2'],
        memberNames: ['Visitante'],
      );
      await db.delete(db.outboxEntries).go();

      await repo.updateAssignment(
        id: id,
        scaleTypeId: 'st1',
        startsOn: DateTime(2026, 9, 21),
        memberIds: ['u9'],
      );
      expect((await dao.getAssignment(id))!.memberIds, ['u9']);

      remote.updateErrors['scale_assignments'] = makeRlsException();
      final worker = OutboxWorker(
        db: db,
        remote: remote,
        isConnected: () async => true,
      );
      await worker.drain();

      final row = (await dao.getAssignment(id))!;
      expect(row.memberIds, ['u1', 'u2']);
      expect(row.memberNames, ['Visitante']);
      expect(await db.outboxEntries.count().getSingle(), 0);
    });
  });

  group('isAssignedTo', () {
    Future<ScaleAssignmentRow> seed({
      List<String> memberIds = const [],
      String? assigneeId,
    }) async {
      await entity.upsert(
        db,
        makeAssignmentJson(memberIds: memberIds, assigneeId: assigneeId),
      );
      return (await dao.getAssignment('sa1'))!;
    }

    test('estar na equipe conta', () async {
      final row = await seed(memberIds: ['u1', 'u2']);
      expect(isAssignedTo(row, 'u2'), isTrue);
    });

    test('ser responsável geral conta, mesmo fora da equipe', () async {
      // Quem lidera o grupo do almoço está escalado no almoço: o resumo
      // "Você está escalado N×" tem de contá-lo.
      final row = await seed(memberIds: ['u1'], assigneeId: 'u9');
      expect(isAssignedTo(row, 'u9'), isTrue);
    });

    test('quem não está na escala não é contado', () async {
      final row = await seed(memberIds: ['u1'], assigneeId: 'u9');
      expect(isAssignedTo(row, 'u5'), isFalse);
    });
  });
}
