import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/sync_providers.dart';

import '../helpers/test_helpers.dart';

/// Fake que roda um gancho no primeiro `fetch` de `profiles` — a primeira
/// entidade do pull. Serve para simular algo que acontece **no meio** de um
/// ciclo de sync.
class _HookedRemoteSource extends FakeRemoteSource {
  void Function()? onFirstProfilesFetch;
  bool _fired = false;

  @override
  Future<List<Map<String, dynamic>>> fetch({
    required String table,
    String? gtColumn,
    Object? gtValue,
    String? orderColumn,
  }) async {
    if (table == 'profiles' && !_fired) {
      _fired = true;
      onFirstProfilesFetch?.call();
    }
    return super.fetch(
      table: table,
      gtColumn: gtColumn,
      gtValue: gtValue,
      orderColumn: orderColumn,
    );
  }
}

void main() {
  late AppDatabase db;
  late _HookedRemoteSource remote;
  late ProviderContainer container;

  setUp(() {
    db = createTestDatabase();
    remote = _HookedRemoteSource();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      remoteSourceProvider.overrideWithValue(remote),
      connectivityCheckProvider.overrideWithValue(() async => true),
      // `overrideWithValue` e não um `Stream.value`: a stream de
      // conectividade emite em microtask, então `isOnlineProvider` leria
      // `null` (= offline) no primeiro frame e o estado sairia sempre
      // `offline`, mascarando o que estes testes medem.
      isOnlineProvider.overrideWithValue(true),
    ]);
  });
  tearDown(() {
    container.dispose();
    db.close();
  });

  /// Escrita otimista + entrada na outbox, como `PrayerRepository.createPost`.
  Future<void> createPostOptimistically(String id) async {
    await db.into(db.prayerFeedRows).insert(
          PrayerFeedRowsCompanion.insert(
            id: id,
            authorId: 'u1',
            title: 'Pedido $id',
            body: 'Corpo do pedido $id',
            createdAt: DateTime.utc(2026, 9, 21),
            updatedAt: DateTime.utc(2026, 9, 21),
          ),
        );
    await enqueueOutboxEntry(
      db,
      entity: 'prayer_feed',
      op: 'insert',
      rowId: id,
      payload: {
        'id': id,
        'title': 'Pedido $id',
        'body': 'Corpo do pedido $id',
        'is_anonymous': false,
        'author_id': 'u1',
      },
    );
  }

  // A faixa "N alterações aguardando envio" foi retirada da UI. Sem ela,
  // qualquer estado que `hasPending` engula fica invisível para o usuário —
  // por isso a ordem de precedência passou a importar.
  group('precedência do estado de sync', () {
    test('um erro de pull aparece mesmo com a fila cheia', () async {
      await createPostOptimistically('post-1');
      // A entrada falha de forma retentável: fica na fila com backoff.
      remote.insertErrors['prayer_posts'] = makeSocketException();
      // E o pull também falha, na primeira entidade.
      remote.fetchErrors['profiles'] = makeSocketException();

      // Um `StreamProvider` sem ouvinte é descartado logo após o `read`, e
      // então `.future` nunca resolve. A inscrição segura o provider e
      // garante que o notifier veja `hasPending == true`.
      final sub = container.listen(hasPendingOutboxProvider, (_, _) {});

      await container.read(syncStatusProvider.notifier).pullAll();

      expect(await db.outboxEntries.count().getSingle(), 1,
          reason: 'a entrada deve continuar na fila');
      expect(await container.read(hasPendingOutboxProvider.future), isTrue);
      // Antes: `hasPending` vinha antes de `_lastError` e o estado era
      // `syncing` — que agora não desenha nada, escondendo a falha.
      expect(container.read(syncStatusProvider), SyncStatus.error);

      sub.close();
    });

    test('offline continua na frente do erro', () async {
      final offline = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
        remoteSourceProvider.overrideWithValue(remote),
        connectivityCheckProvider.overrideWithValue(() async => false),
        isOnlineProvider.overrideWithValue(false),
      ]);
      addTearDown(offline.dispose);

      remote.fetchErrors['profiles'] = makeSocketException();
      await offline.read(syncStatusProvider.notifier).pullAll();

      expect(offline.read(syncStatusProvider), SyncStatus.offline);
    });

    test('sem erro e com a fila vazia o estado é idle', () async {
      await container.read(syncStatusProvider.notifier).pullAll();

      expect(container.read(syncStatusProvider), SyncStatus.idle);
    });
  });

  // O bug: `pullAll()` descartava um pedido que chegasse durante um ciclo.
  // A escrita que entrasse na fila depois do `drain()` ficava presa até o
  // próximo resume do app — e a fila nunca volta de vazia para cheia, então o
  // gatilho de pendentes do `SyncCoordinator` também não dispararia de novo.
  group('gatilho concorrente', () {
    test('escrita que entra no meio do ciclo ainda é enviada', () async {
      await createPostOptimistically('post-1');

      remote.onFirstProfilesFetch = () {
        // Já passou pelo drain deste ciclo. É exatamente o que acontece
        // quando o usuário salva algo enquanto um sync está em curso.
        unawaited(() async {
          await createPostOptimistically('post-2');
          await container.read(syncStatusProvider.notifier).pullAll();
        }());
      };

      await container.read(syncStatusProvider.notifier).pullAll();

      expect(await db.outboxEntries.count().getSingle(), 0,
          reason: 'a fila deve ficar vazia sem depender de outro gatilho');
      final sent = remote.insertedPayloads['prayer_posts'] ?? const [];
      expect(sent.map((p) => p['id']), containsAll(['post-1', 'post-2']));
      expect(container.read(syncStatusProvider), SyncStatus.idle);
    });

    test('sem pedido concorrente o ciclo roda uma única vez', () async {
      await createPostOptimistically('post-1');

      await container.read(syncStatusProvider.notifier).pullAll();

      final profileFetches =
          remote.calls.where((c) => c.table == 'profiles').length;
      expect(profileFetches, 1);
    });
  });
}
