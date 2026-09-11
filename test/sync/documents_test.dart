import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/daos/documents_dao.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/repositories/documents_repository.dart';
import 'package:veredas/data/sync/outbox_worker.dart';
import 'package:veredas/data/sync/sync_entity.dart';
import 'package:veredas/data/sync/sync_service.dart';

import '../helpers/test_helpers.dart';

Map<String, dynamic> makeDocumentJson({
  String id = 'd1',
  String title = 'Manual de discipulado',
  String? description,
  String sourceType = 'link',
  String? url = 'https://drive.google.com/file/abc',
  String? storagePath,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  return {
    'id': id,
    'title': title,
    'description': description,
    'source_type': sourceType,
    'url': url,
    'storage_path': storagePath,
    'created_by': null,
    'created_at': (createdAt ?? DateTime.utc(2026, 8, 1)).toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.utc(2026, 8, 1)).toIso8601String(),
    if (deletedAt != null) 'deleted_at': deletedAt.toIso8601String(),
  };
}

void main() {
  late AppDatabase db;
  late FakeRemoteSource remote;
  late DocumentsRepository repo;
  late DocumentsDao dao;

  setUp(() {
    db = createTestDatabase();
    remote = FakeRemoteSource();
    repo = DocumentsRepository(db);
    dao = DocumentsDao(db);
  });
  tearDown(() => db.close());

  Future<void> seed(List<Map<String, dynamic>> rows) async {
    for (final r in rows) {
      await syncEntityByName('documents')!.upsert(db, r);
    }
  }

  group('ordenação da lista', () {
    setUp(() async {
      await seed([
        makeDocumentJson(
          id: 'b',
          title: 'Bíblia — plano de leitura',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 8, 20),
        ),
        makeDocumentJson(
          id: 'a',
          title: 'Apostila de missões',
          createdAt: DateTime.utc(2026, 8, 15),
          updatedAt: DateTime.utc(2026, 8, 16),
        ),
        makeDocumentJson(
          id: 'c',
          title: 'Cronograma anual',
          createdAt: DateTime.utc(2026, 5, 10),
          updatedAt: DateTime.utc(2026, 5, 10),
        ),
      ]);
    });

    Future<List<String>> titlesFor(DocumentSort sort) async {
      final rows = await dao.watchDocuments(sort).first;
      return rows.map((r) => r.title).toList();
    }

    test('alterados recentemente', () async {
      expect(await titlesFor(DocumentSort.recentlyUpdated), [
        'Bíblia — plano de leitura', // 20/08
        'Apostila de missões', //       16/08
        'Cronograma anual', //          10/05
      ]);
    });

    test('adicionados recentemente é diferente de alterados', () async {
      // O 'b' foi criado primeiro e alterado por último: se as duas ordenações
      // devolvessem o mesmo, uma das duas estaria lendo a coluna errada.
      expect(await titlesFor(DocumentSort.recentlyAdded), [
        'Apostila de missões', //       criado 15/08
        'Cronograma anual', //          criado 10/05
        'Bíblia — plano de leitura', // criado 01/01
      ]);
    });

    test('nome A–Z e Z–A', () async {
      expect(await titlesFor(DocumentSort.titleAsc), [
        'Apostila de missões',
        'Bíblia — plano de leitura',
        'Cronograma anual',
      ]);
      expect(
        await titlesFor(DocumentSort.titleDesc),
        (await titlesFor(DocumentSort.titleAsc)).reversed.toList(),
      );
    });
  });

  group('escrita pela outbox', () {
    test('criar enfileira insert e mostra o item na hora', () async {
      final id = await repo.createLink(
        title: 'Manual',
        url: 'https://drive.google.com/file/abc',
      );

      // Cache otimista: a UI já mostra.
      final rows = await dao.watchDocuments(DocumentSort.titleAsc).first;
      expect(rows.map((r) => r.id), [id]);
      expect(rows.first.sourceType, 'link');

      final entry = await db.select(db.outboxEntries).getSingle();
      expect(entry.entity, 'documents');
      expect(entry.op, 'insert');
      expect(jsonDecode(entry.payload)['source_type'], 'link');
    });

    test('excluir é UPDATE de deleted_at, não DELETE', () async {
      final id = await repo.createLink(title: 'Manual', url: 'https://x.org/a');
      await (db.delete(db.outboxEntries)).go();

      await repo.deleteDocument(id);

      // Um DELETE físico apagaria a linha do servidor sem deixar rastro. O
      // soft delete permite recuperação e é o que a policy de leitura filtra.
      final entry = await db.select(db.outboxEntries).getSingle();
      expect(entry.op, 'update');
      expect(jsonDecode(entry.payload)['deleted_at'], isNotNull);

      // Localmente o item sai na hora (o cache não guarda deleted_at).
      expect(await dao.findById(id), isNull);
    });

    test('a exclusão chega ao servidor na tabela documents', () async {
      final id = await repo.createLink(title: 'Manual', url: 'https://x.org/a');
      await repo.deleteDocument(id);

      final worker = OutboxWorker(
        db: db,
        remote: remote,
        isConnected: () async => true,
      );
      await worker.drain();

      expect(remote.updatedPayloads['documents']?.length, 1);
      expect(await db.outboxEntries.count().getSingle(), 0);
    });
  });

  group('sync', () {
    test('fullReplace remove o que o servidor não devolve mais', () async {
      final syncService = SyncService(db: db, remote: remote);
      final entity = syncEntityByName('documents')!;

      remote.fetchData['documents'] = [
        makeDocumentJson(id: 'd1', title: 'Manual'),
        makeDocumentJson(id: 'd2', title: 'Apostila'),
      ];
      await syncService.pull(entity);
      expect(await db.documentRows.count().getSingle(), 2);

      // O admin apagou o 'd2'. A policy `documents_select` filtra
      // `deleted_at is null`, então o servidor simplesmente para de devolvê-lo
      // — não há lápide. É por isso que esta entidade é fullReplace: com
      // incremental o item ficaria no cache para sempre.
      remote.fetchData['documents'] = [
        makeDocumentJson(id: 'd1', title: 'Manual'),
      ];
      await syncService.pull(entity);

      final rows = await db.select(db.documentRows).get();
      expect(rows.map((r) => r.id), ['d1']);
    });

    test('a entidade documents está registrada como fullReplace', () {
      final entity = syncEntityByName('documents')!;
      expect(entity.mode, SyncMode.fullReplace);
      // Escreve na própria tabela: não é view, então não precisa de override.
      expect(entity.writeTable, 'documents');
    });

    test('source_type ausente no JSON não derruba o pull', () async {
      // Um servidor mais antigo (ou uma linha criada antes da coluna) não
      // manda o campo. Cair para 'link' mantém o app funcionando em vez de
      // estourar no meio do pull e abortar as entidades seguintes.
      await syncEntityByName('documents')!.upsert(db, {
        'id': 'legacy',
        'title': 'Antigo',
        'url': 'https://x.org/a',
        'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
      });

      final row = await dao.findById('legacy');
      expect(row?.sourceType, 'link');
    });
  });
}
