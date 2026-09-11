import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/sync_providers.dart';

import '../helpers/test_helpers.dart';

/// Fake que só devolve a oração no `fetch` **depois** de tê-la recebido num
/// `insert`, como um servidor real.
///
/// Sem esse encadeamento o teste de ordem passaria mesmo com a ordem errada:
/// se o `fetchData` fosse fixo, o pull traria a linha de volta e esconderia o
/// fato de o `clear()` do fullReplace ter apagado a escrita otimista.
class _EchoingRemoteSource extends FakeRemoteSource {
  @override
  Future<List<Map<String, dynamic>>> fetch({
    required String table,
    String? gtColumn,
    Object? gtValue,
    String? orderColumn,
  }) async {
    final base = await super.fetch(
      table: table,
      gtColumn: gtColumn,
      gtValue: gtValue,
      orderColumn: orderColumn,
    );
    if (table != 'prayer_feed') return base;

    // A view devolve o post com os campos calculados que o cache espelha.
    return (insertedPayloads['prayer_posts'] ?? const [])
        .map((p) => <String, dynamic>{
              ...p,
              'author_name': 'Alisson Schimitt',
              'author_avatar_url': null,
              'praying_count': 0,
              'comment_count': 0,
              'is_praying': false,
              'created_at': DateTime.utc(2026, 8, 28).toIso8601String(),
              'updated_at': DateTime.utc(2026, 8, 28).toIso8601String(),
            })
        .toList();
  }
}

void main() {
  late AppDatabase db;
  late _EchoingRemoteSource remote;
  late ProviderContainer container;

  setUp(() {
    db = createTestDatabase();
    remote = _EchoingRemoteSource();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      remoteSourceProvider.overrideWithValue(remote),
      connectivityCheckProvider.overrideWithValue(() async => true),
      connectivityStreamProvider.overrideWith(
        (ref) => Stream.value([ConnectivityResult.wifi]),
      ),
    ]);
  });
  tearDown(() {
    container.dispose();
    db.close();
  });

  // O bug: `pullAll()` puxava antes de drenar. O pull de `prayer_feed` é
  // fullReplace, então o `clear()` apagava a oração recém-criada que ainda
  // estava na fila. Ela desaparecia da tela e só voltava no sync seguinte.
  group('ciclo de sync — ordem entre drenar e puxar', () {
    /// Simula o que `PrayerRepository.createPost` faz: escrita otimista no
    /// cache + entrada na outbox, numa transação.
    Future<void> createPostOptimistically() async {
      await db.into(db.prayerFeedRows).insert(
            PrayerFeedRowsCompanion.insert(
              id: 'post-1',
              authorId: 'u1',
              title: 'Teste de sync',
              body: 'Validando envio para o Supabase',
              createdAt: DateTime.utc(2026, 8, 28),
              updatedAt: DateTime.utc(2026, 8, 28),
            ),
          );
      await enqueueOutboxEntry(
        db,
        entity: 'prayer_feed',
        op: 'insert',
        rowId: 'post-1',
        payload: {
          'id': 'post-1',
          'title': 'Teste de sync',
          'body': 'Validando envio para o Supabase',
          'is_anonymous': false,
          'author_id': 'u1',
        },
      );
    }

    test('a oração criada sobrevive ao ciclo e chega ao servidor', () async {
      await createPostOptimistically();

      await container.read(syncStatusProvider.notifier).pullAll();

      // Chegou ao servidor, na tabela — não na view.
      expect(remote.insertedPayloads['prayer_posts']?.length, 1);
      // E continua visível: o pull veio depois do envio, então o fullReplace
      // repopulou a linha em vez de apagá-la.
      expect(await db.prayerFeedRows.count().getSingle(), 1);
      expect(await db.outboxEntries.count().getSingle(), 0);
    });

    test('o insert acontece antes do fetch da view', () async {
      await createPostOptimistically();

      await container.read(syncStatusProvider.notifier).pullAll();

      final sequence = remote.calls
          .where((c) => c.table == 'prayer_posts' || c.table == 'prayer_feed')
          .map((c) => '${c.method}:${c.table}')
          .toList();

      expect(
        sequence.indexOf('insert:prayer_posts'),
        lessThan(sequence.indexOf('fetch:prayer_feed')),
      );
    });

    test('o pull popula o cache com o que a view calcula', () async {
      await createPostOptimistically();

      await container.read(syncStatusProvider.notifier).pullAll();

      // O otimismo não sabe o nome do autor (a view faz join com profiles);
      // depois do ciclo, o cache tem o valor do servidor.
      final row = await db.select(db.prayerFeedRows).getSingle();
      expect(row.authorName, 'Alisson Schimitt');
    });
  });
}
