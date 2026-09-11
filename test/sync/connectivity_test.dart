import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/infra_providers.dart';

import '../helpers/test_helpers.dart';

void main() {
  late AppDatabase db;
  late FakeRemoteSource remote;
  late FakeConnectivityMonitor monitor;
  late ProviderContainer container;
  ProviderSubscription<AsyncValue<List<ConnectivityResult>>>? keepAlive;

  /// Liga o provider e espera o primeiro valor.
  ///
  /// Só é chamado **depois** de o teste configurar o `monitor`: ligar o provider
  /// no `setUp` faria a semeadura acontecer com o estado padrão, e um teste que
  /// pede "sem rede" leria "wifi".
  ///
  /// A subscription fica viva pelo resto do teste porque o Riverpod 3 descarta
  /// providers sem ouvintes; recriado, o `.future` do novo elemento ficaria
  /// pendente e completaria com erro no `container.dispose()`.
  Future<void> settleConnectivity() async {
    keepAlive = container.listen(connectivityStreamProvider, (_, _) {});
    // O timeout é curto de propósito: se a semeadura via `current()` for
    // removida, o provider nunca emite (o fake não gera mudanças por conta
    // própria) e o teste ficaria pendurado até o limite de 30s do test runner,
    // sem dizer o motivo. Assim a regressão falha em 2s e explica o porquê.
    await container.read(connectivityStreamProvider.future).timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw TimeoutException(
            'connectivityStreamProvider não emitiu: o estado atual não foi '
            'semeado, então o app não sabe se há rede até ela oscilar',
          ),
        );
  }

  /// Espera `isOnlineProvider` chegar a [expected], ou desiste.
  ///
  /// Um evento de rede atravessa vários hops assíncronos até o provider
  /// derivado (controller broadcast → `async*` → StreamProvider →
  /// `isOnlineProvider`), então um único microtask não basta. Esperar a
  /// condição em vez de cravar um `delay` evita teste sensível a timing — quem
  /// falha, se não chegar, é o `expect` de quem chamou.
  Future<void> waitUntilOnline(bool expected) async {
    for (var i = 0; i < 50; i++) {
      if (container.read(isOnlineProvider) == expected) return;
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    db = createTestDatabase();
    remote = FakeRemoteSource();
    monitor = FakeConnectivityMonitor();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      remoteSourceProvider.overrideWithValue(remote),
      connectivityMonitorProvider.overrideWithValue(monitor),
    ]);
  });
  tearDown(() {
    keepAlive?.close();
    keepAlive = null;
    // O monitor antes do container: fechar o stream primeiro deixa o
    // StreamProvider terminar normalmente.
    monitor.dispose();
    container.dispose();
    db.close();
  });

  // O bug: o provider escutava só `onConnectivityChanged`, que entrega apenas
  // MUDANÇAS. Sem nenhuma oscilação de rede o provider ficava sem valor,
  // `isOnlineProvider` lia isso como offline, e o app se comportava como se
  // não houvesse internet — com internet.
  group('connectivityStreamProvider', () {
    test('semeia o estado atual sem depender de mudança de rede', () async {
      await settleConnectivity();

      // Nenhum evento de mudança foi emitido — só `current()` respondeu.
      expect(monitor.currentCalls, 1);
      expect(container.read(isOnlineProvider), true);
    });

    test('sem rede, isOnline é false', () async {
      monitor.currentResult = const [ConnectivityResult.none];

      await settleConnectivity();

      expect(container.read(isOnlineProvider), false);
    });

    test('mudança de rede depois do estado inicial propaga', () async {
      monitor.currentResult = const [ConnectivityResult.none];
      await settleConnectivity();
      expect(container.read(isOnlineProvider), false);

      monitor.emit(const [ConnectivityResult.wifi]);
      await waitUntilOnline(true);

      expect(container.read(isOnlineProvider), true);
    });

    test('mais de uma interface ativa conta como online', () async {
      monitor.currentResult = const [
        ConnectivityResult.wifi,
        ConnectivityResult.mobile,
      ];

      await settleConnectivity();

      expect(container.read(isOnlineProvider), true);
    });
  });

  // Este é o teste que importa: conectividade não é cosmética, ela decide se a
  // fila de escrita anda. `OutboxWorker.drain()` começa com
  // `if (!await isConnected()) return`, então um falso "offline" prendia toda
  // escrita no aparelho — foi assim que uma oração criada no celular nunca
  // chegou ao Supabase.
  group('conectividade x fila de escrita', () {
    Future<void> enqueueAnnouncement() async {
      await enqueueOutboxEntry(
        db,
        entity: 'announcements',
        op: 'insert',
        rowId: 'a1',
        payload: {'id': 'a1', 'body': 'Aviso'},
      );
    }

    test('online: a fila drena e a escrita chega ao servidor', () async {
      await enqueueAnnouncement();
      await settleConnectivity();

      await container.read(outboxWorkerProvider).drain();

      expect(remote.insertedPayloads['announcements']?.length, 1);
      expect(await db.outboxEntries.count().getSingle(), 0);
    });

    test('offline: a escrita fica na fila, sem tentar a rede', () async {
      monitor.currentResult = const [ConnectivityResult.none];
      await enqueueAnnouncement();
      await settleConnectivity();

      await container.read(outboxWorkerProvider).drain();

      // Nada foi enviado, e nada foi perdido: a entrada continua na fila para
      // o próximo gatilho.
      expect(remote.calls, isEmpty);
      expect(await db.outboxEntries.count().getSingle(), 1);
    });

    test('volta da conexão libera a escrita que estava presa', () async {
      monitor.currentResult = const [ConnectivityResult.none];
      await enqueueAnnouncement();
      await settleConnectivity();

      await container.read(outboxWorkerProvider).drain();
      expect(await db.outboxEntries.count().getSingle(), 1);

      monitor.emit(const [ConnectivityResult.wifi]);
      await waitUntilOnline(true);

      await container.read(outboxWorkerProvider).drain();

      expect(remote.insertedPayloads['announcements']?.length, 1);
      expect(await db.outboxEntries.count().getSingle(), 0);

    });
  });
}
