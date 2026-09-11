import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/sync/outbox_worker.dart';
import 'package:veredas/data/sync/sync_entity.dart';

import '../helpers/test_helpers.dart';

void main() {
  late AppDatabase db;
  late FakeRemoteSource remote;
  late OutboxWorker worker;

  setUp(() {
    db = createTestDatabase();
    remote = FakeRemoteSource();
    worker = OutboxWorker(
      db: db,
      remote: remote,
      isConnected: () async => true,
    );
  });
  tearDown(() => db.close());

  // Helper: insere uma linha no cache e cria a entrada na outbox,
  // simulando o que o repositório faria numa escrita otimista.
  Future<void> optimisticInsert({
    required String entity,
    required String table,
    required String rowId,
    required Map<String, dynamic> remotePayload,
  }) async {
    // Aplica a mudança otimista no cache.
    final syncEntity = syncEntityByName(entity)!;
    final now = DateTime.now().toUtc().toIso8601String();
    await syncEntity.upsert(db, {
      ...remotePayload,
      'created_at': remotePayload['created_at'] ?? now,
      'updated_at': now,
    });

    // Insere na outbox.
    await enqueueOutboxEntry(
      db,
      entity: entity,
      op: 'insert',
      rowId: rowId,
      payload: remotePayload,
    );
  }

  group('OutboxWorker.drain — aceite 4: esvazia a fila ao voltar a conexão',
      () {
    test('envia insert pendente e remove da fila', () async {
      const payload = {
        'id': 'a1',
        'title': 'Novo aviso',
        'body': 'Corpo',
      };
      await optimisticInsert(
        entity: 'announcements',
        table: 'announcements',
        rowId: 'a1',
        remotePayload: payload,
      );

      // A fila tem 1 entrada.
      expect(await db.outboxEntries.count().getSingle(), 1);

      await worker.drain();

      // A fila esvaziou.
      expect(await db.outboxEntries.count().getSingle(), 0);
      // O insert chegou ao servidor.
      expect(remote.insertedPayloads['announcements']?.length, 1);
      expect(remote.insertedPayloads['announcements']!.first, payload);
    });

    test('envia update pendente e remove da fila', () async {
      // Estado inicial: linha no cache.
      await db.into(db.announcementRows).insert(
            AnnouncementRowsCompanion.insert(
              id: 'a1',
              body: 'Original',
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      // Snapshot anterior (para rollback).
      final previousRow = (await db.select(db.announcementRows).getSingle())
          .toJson();

      // Atualiza otimistamente.
      await db.into(db.announcementRows).insertOnConflictUpdate(
            AnnouncementRow(
              id: 'a1',
              body: 'Editado',
              pinned: false,
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.now(),
            ),
          );

      await enqueueOutboxEntry(
        db,
        entity: 'announcements',
        op: 'update',
        rowId: 'a1',
        payload: {'body': 'Editado'},
        previousRow: previousRow,
      );

      await worker.drain();

      expect(await db.outboxEntries.count().getSingle(), 0);
      expect(remote.updatedPayloads['announcements']?.length, 1);
      expect(remote.updatedPayloads['announcements']!.first, {'body': 'Editado'});
    });

    test('envia delete pendente e remove da fila', () async {
      await db.into(db.announcementRows).insert(
            AnnouncementRowsCompanion.insert(
              id: 'a1',
              body: 'A ser apagado',
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      final previousRow = (await db.select(db.announcementRows).getSingle())
          .toJson();

      // Apaga otimistamente.
      await (db.delete(db.announcementRows)
            ..where((t) => t.id.equals('a1')))
          .go();

      await enqueueOutboxEntry(
        db,
        entity: 'announcements',
        op: 'delete',
        rowId: 'a1',
        previousRow: previousRow,
      );

      await worker.drain();

      expect(await db.outboxEntries.count().getSingle(), 0);
      // O delete chegou ao servidor.
      final deleteCall = remote.calls
          .where((c) => c.method == 'delete' && c.table == 'announcements')
          .toList();
      expect(deleteCall.length, 1);
    });

    test('não drena se não houver conexão', () async {
      await optimisticInsert(
        entity: 'announcements',
        table: 'announcements',
        rowId: 'a1',
        remotePayload: {'id': 'a1', 'body': 'Teste'},
      );

      worker = OutboxWorker(
        db: db,
        remote: remote,
        isConnected: () async => false,
      );
      await worker.drain();

      // A fila permanece.
      expect(await db.outboxEntries.count().getSingle(), 1);
      expect(remote.calls, isEmpty);
    });
  });

  group('OutboxWorker.drain — aceite 5: 403 do RLS reverte o cache', () {
    test('insert recusado (RLS 42501) remove a linha otimista e a entrada',
        () async {
      const payload = {
        'id': 'a1',
        'title': 'Aviso',
        'body': 'Corpo',
      };
      await optimisticInsert(
        entity: 'announcements',
        table: 'announcements',
        rowId: 'a1',
        remotePayload: payload,
      );

      // O servidor vai recusar com 42501.
      remote.insertErrors['announcements'] = makeRlsException();

      await worker.drain();

      // A fila esvaziou (a entrada foi removida).
      expect(await db.outboxEntries.count().getSingle(), 0);
      // A linha otimista foi revertida (removida do cache).
      expect(await db.announcementRows.count().getSingle(), 0);
      // O erro foi registrado no sync_state.
      final state = await (db.select(db.syncStates)
            ..where((t) => t.entity.equals('announcements')))
          .getSingle();
      expect(state.lastError, AppErrorCode.permissionDenied.name);
    });

    test('update recusado (RLS 42501) restaura o snapshot anterior', () async {
      // Estado inicial: linha no cache com body "Original".
      await db.into(db.announcementRows).insert(
            AnnouncementRowsCompanion.insert(
              id: 'a1',
              body: 'Original',
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      final previousRow = (await db.select(db.announcementRows).getSingle())
          .toJson();

      // Atualiza otimistamente para "Editado".
      await db.into(db.announcementRows).insertOnConflictUpdate(
            AnnouncementRow(
              id: 'a1',
              body: 'Editado',
              pinned: false,
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.now(),
            ),
          );

      await enqueueOutboxEntry(
        db,
        entity: 'announcements',
        op: 'update',
        rowId: 'a1',
        payload: {'body': 'Editado'},
        previousRow: previousRow,
      );

      // O servidor vai recusar.
      remote.updateErrors['announcements'] = makeRlsException();

      await worker.drain();

      // A fila esvaziou.
      expect(await db.outboxEntries.count().getSingle(), 0);
      // O cache foi revertido para "Original".
      final row = await db.select(db.announcementRows).getSingle();
      expect(row.body, 'Original');
    });

    test('delete recusado (RLS 42501) restaura a linha apagada', () async {
      await db.into(db.announcementRows).insert(
            AnnouncementRowsCompanion.insert(
              id: 'a1',
              body: 'Aviso importante',
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      final previousRow = (await db.select(db.announcementRows).getSingle())
          .toJson();

      // Apaga otimistamente.
      await (db.delete(db.announcementRows)
            ..where((t) => t.id.equals('a1')))
          .go();
      expect(await db.announcementRows.count().getSingle(), 0);

      await enqueueOutboxEntry(
        db,
        entity: 'announcements',
        op: 'delete',
        rowId: 'a1',
        previousRow: previousRow,
      );

      // O servidor recusa o delete.
      remote.deleteErrors['announcements'] = makeRlsException();

      await worker.drain();

      // A fila esvaziou.
      expect(await db.outboxEntries.count().getSingle(), 0);
      // A linha foi restaurada.
      final row = await db.select(db.announcementRows).getSingle();
      expect(row.body, 'Aviso importante');
    });
  });

  group('OutboxWorker.drain — caso 0-linhas (permissionDeniedOrStale)', () {
    test('update que afeta 0 linhas reverte o cache', () async {
      await db.into(db.announcementRows).insert(
            AnnouncementRowsCompanion.insert(
              id: 'a1',
              body: 'Original',
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      final previousRow = (await db.select(db.announcementRows).getSingle())
          .toJson();

      // Atualiza otimistamente.
      await db.into(db.announcementRows).insertOnConflictUpdate(
            AnnouncementRow(
              id: 'a1',
              body: 'Editado',
              pinned: false,
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.now(),
            ),
          );

      await enqueueOutboxEntry(
        db,
        entity: 'announcements',
        op: 'update',
        rowId: 'a1',
        payload: {'body': 'Editado'},
        previousRow: previousRow,
      );

      // O servidor devolve 0 linhas afetadas (array vazio).
      remote.updateResults['announcements'] = [];

      await worker.drain();

      // A fila esvaziou.
      expect(await db.outboxEntries.count().getSingle(), 0);
      // O cache foi revertido.
      final row = await db.select(db.announcementRows).getSingle();
      expect(row.body, 'Original');
      // O erro registrado é permissionDeniedOrStale, não permissionDenied.
      final state = await (db.select(db.syncStates)
            ..where((t) => t.entity.equals('announcements')))
          .getSingle();
      expect(state.lastError, AppErrorCode.permissionDeniedOrStale.name);
    });

    test('delete que afeta 0 linhas restaura a linha', () async {
      await db.into(db.announcementRows).insert(
            AnnouncementRowsCompanion.insert(
              id: 'a1',
              body: 'Não apaga',
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );

      final previousRow = (await db.select(db.announcementRows).getSingle())
          .toJson();

      await (db.delete(db.announcementRows)
            ..where((t) => t.id.equals('a1')))
          .go();

      await enqueueOutboxEntry(
        db,
        entity: 'announcements',
        op: 'delete',
        rowId: 'a1',
        previousRow: previousRow,
      );

      // O servidor devolve 0 linhas.
      remote.deleteResults['announcements'] = [];

      await worker.drain();

      expect(await db.outboxEntries.count().getSingle(), 0);
      final row = await db.select(db.announcementRows).getSingle();
      expect(row.body, 'Não apaga');
    });
  });

  group('OutboxWorker.drain — rede/timeout mantém na fila com backoff', () {
    test('erro de rede mantém a entrada e agenda retry', () async {
      await optimisticInsert(
        entity: 'announcements',
        table: 'announcements',
        rowId: 'a1',
        remotePayload: {'id': 'a1', 'body': 'Teste'},
      );

      remote.insertErrors['announcements'] = makeSocketException();

      await worker.drain();

      // A entrada permanece na fila.
      expect(await db.outboxEntries.count().getSingle(), 1);
      final entry = await db.select(db.outboxEntries).getSingle();
      expect(entry.attempts, 1);
      expect(entry.nextAttemptAt, isNotNull);
      expect(entry.lastError, AppErrorCode.noConnection.name);
    });

    test('entrada com nextAttemptAt no futuro não é processada', () async {
      await optimisticInsert(
        entity: 'announcements',
        table: 'announcements',
        rowId: 'a1',
        remotePayload: {'id': 'a1', 'body': 'Teste'},
      );

      // Marca nextAttemptAt no futuro.
      await (db.update(db.outboxEntries)
            ..where((t) => t.id.equals(1)))
          .write(
        OutboxEntriesCompanion(
          nextAttemptAt: Value(DateTime.now().add(const Duration(hours: 1))),
        ),
      );

      await worker.drain();

      // Não foi processada.
      expect(await db.outboxEntries.count().getSingle(), 1);
      expect(remote.calls, isEmpty);
    });

    test('entrada com nextAttemptAt no passado é processada', () async {
      await optimisticInsert(
        entity: 'announcements',
        table: 'announcements',
        rowId: 'a1',
        remotePayload: {'id': 'a1', 'body': 'Teste'},
      );

      await (db.update(db.outboxEntries)
            ..where((t) => t.id.equals(1)))
          .write(
        OutboxEntriesCompanion(
          nextAttemptAt: Value(DateTime.now().subtract(const Duration(minutes: 5))),
        ),
      );

      await worker.drain();

      expect(await db.outboxEntries.count().getSingle(), 0);
      expect(remote.insertedPayloads['announcements']?.length, 1);
    });

    test('para o drain no primeiro erro de rede', () async {
      // Duas entradas.
      await optimisticInsert(
        entity: 'announcements',
        table: 'announcements',
        rowId: 'a1',
        remotePayload: {'id': 'a1', 'body': 'A'},
      );
      await optimisticInsert(
        entity: 'announcements',
        table: 'announcements',
        rowId: 'a2',
        remotePayload: {'id': 'a2', 'body': 'B'},
      );

      // A primeira falha com erro de rede.
      remote.insertErrors['announcements'] = makeSocketException();

      await worker.drain();

      // A segunda entrada não foi tentada (drain parou).
      expect(await db.outboxEntries.count().getSingle(), 2);
    });
  });

  group('OutboxWorker — backoff', () {
    test('backoffDelay cresce exponencialmente', () {
      expect(OutboxWorker.backoffDelay(0), const Duration(seconds: 1));
      expect(OutboxWorker.backoffDelay(1), const Duration(seconds: 2));
      expect(OutboxWorker.backoffDelay(2), const Duration(seconds: 4));
      expect(OutboxWorker.backoffDelay(3), const Duration(seconds: 8));
      expect(OutboxWorker.backoffDelay(8), const Duration(seconds: 256));
      // Cap em 256s.
      expect(OutboxWorker.backoffDelay(10), const Duration(seconds: 256));
    });
  });

  group('OutboxWorker — aceite 3: escrita offline aparece na UI', () {
    test('o stream do drift emite imediatamente após a escrita otimista',
        () async {
      final emissions = <int>[];
      final sub = db
          .select(db.announcementRows)
          .watch()
          .listen((rows) => emissions.add(rows.length));

      await pumpEventQueue();

      // Escrita otimista (sem rede, sem drain).
      await optimisticInsert(
        entity: 'announcements',
        table: 'announcements',
        rowId: 'a1',
        remotePayload: {'id': 'a1', 'body': 'Offline'},
      );

      await pumpEventQueue();
      await sub.cancel();

      // O stream emitiu 0 → 1 imediatamente, sem esperar o drain.
      expect(emissions, [0, 1]);
      // E a entrada está na outbox.
      expect(await db.outboxEntries.count().getSingle(), 1);
    });
  });

  group('OutboxWorker — ordem de drenagem', () {
    test('processa em ordem de inserção (id crescente)', () async {
      await optimisticInsert(
        entity: 'announcements',
        table: 'announcements',
        rowId: 'a1',
        remotePayload: {'id': 'a1', 'body': 'Primeiro'},
      );
      await optimisticInsert(
        entity: 'announcements',
        table: 'announcements',
        rowId: 'a2',
        remotePayload: {'id': 'a2', 'body': 'Segundo'},
      );

      await worker.drain();

      // Verifica a ordem das chamadas insert.
      final insertCalls = remote.calls
          .where((c) => c.method == 'insert')
          .toList();
      expect(insertCalls.length, 2);
      expect(insertCalls[0].extra!['id'], 'a1');
      expect(insertCalls[1].extra!['id'], 'a2');
    });
  });

  // O mural de oração lê da view `prayer_feed` e escreve na tabela
  // `prayer_posts`. Enviar a escrita para a view falha no servidor — ela tem
  // `join profiles` (view com mais de uma entrada no FROM não é
  // auto-updatable) e só recebeu `grant select`. O sintoma era uma oração
  // criada no celular que nunca chegava ao Supabase e desaparecia do aparelho
  // na próxima drenagem da fila.
  group('OutboxWorker — entidade que lê de view e escreve em tabela', () {
    Future<void> enqueuePrayerPost(String op, {
      Map<String, dynamic>? payload,
      Map<String, dynamic>? previousRow,
    }) async {
      await enqueueOutboxEntry(
        db,
        entity: 'prayer_feed',
        op: op,
        rowId: 'post-1',
        payload: payload ?? const {},
        previousRow: previousRow,
      );
    }

    test('insert de oração vai para prayer_posts, não para a view', () async {
      await enqueuePrayerPost('insert', payload: {
        'id': 'post-1',
        'title': 'Pela família',
        'body': 'Peço oração pela minha família.',
        'is_anonymous': false,
        'author_id': 'u1',
      });

      await worker.drain();

      expect(remote.insertedPayloads['prayer_posts']?.length, 1);
      expect(remote.insertedPayloads['prayer_feed'], isNull);
      expect(await db.outboxEntries.count().getSingle(), 0);
    });

    test('update de oração vai para prayer_posts', () async {
      await db.into(db.prayerFeedRows).insert(
            PrayerFeedRowsCompanion.insert(
              id: 'post-1',
              authorId: 'u1',
              title: 'Original',
              body: 'Corpo',
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          );
      await enqueuePrayerPost('update', payload: {'title': 'Editado'});

      await worker.drain();

      expect(remote.updatedPayloads['prayer_posts']?.length, 1);
      expect(remote.updatedPayloads['prayer_feed'], isNull);
    });

    test('delete de oração vai para prayer_posts', () async {
      await enqueuePrayerPost('delete');

      await worker.drain();

      final deletes = remote.calls.where((c) => c.method == 'delete');
      expect(deletes.map((c) => c.table), ['prayer_posts']);
    });

    test('writeTable cai em remoteTable para as demais entidades', () {
      // Guarda contra o inverso do bug: alguém apontar writeTable à toa e
      // quebrar uma entidade que sempre escreveu na própria tabela.
      for (final entity in syncEntities) {
        if (entity.name == 'prayer_feed') {
          expect(entity.writeTable, 'prayer_posts');
          expect(entity.remoteTable, 'prayer_feed');
        } else {
          expect(
            entity.writeTable,
            entity.remoteTable,
            reason: '${entity.name} não deveria ter writeTable próprio',
          );
        }
      }
    });
  });
}
