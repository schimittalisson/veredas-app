import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/report_reason.dart';
import 'package:veredas/data/repositories/moderation_repository.dart';
import 'package:veredas/data/sync/outbox_worker.dart';
import 'package:veredas/data/sync/sync_entity.dart';
import 'package:veredas/data/sync/sync_service.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/moderation_providers.dart';
import 'package:veredas/providers/prayer_providers.dart';

import '../helpers/test_helpers.dart';

const _me = 'u-me';
const _other = 'u-other';
const _third = 'u-third';

Map<String, dynamic> _feedJson({
  required String id,
  required String authorId,
  bool isAnonymous = false,
  String title = 'Pedido',
}) {
  final ts = DateTime.utc(2026, 9, 1).toIso8601String();
  return {
    'id': id,
    'author_id': authorId,
    'title': title,
    'body': 'Corpo do pedido',
    'is_anonymous': isAnonymous,
    'answered_at': null,
    'answer_note': null,
    'author_name': isAnonymous ? null : 'Autor $authorId',
    'author_avatar_url': null,
    'praying_count': 0,
    'comment_count': 0,
    'is_praying': false,
    'created_at': ts,
    'updated_at': ts,
  };
}

Map<String, dynamic> _reportJson({
  required String id,
  required String reporterId,
  required String postId,
  DateTime? resolvedAt,
}) {
  final ts = DateTime.utc(2026, 9, 2).toIso8601String();
  return {
    'id': id,
    'reporter_id': reporterId,
    'post_id': postId,
    'reason': 'offensive',
    'post_title': 'Pedido',
    'post_body': 'Corpo do pedido',
    'post_author_id': _other,
    'post_is_anonymous': false,
    'resolved_at': resolvedAt?.toIso8601String(),
    'resolved_by': null,
    'created_at': ts,
    'updated_at': ts,
  };
}

void main() {
  late AppDatabase db;
  late FakeRemoteSource remote;
  late ModerationRepository repo;

  OutboxWorker worker() => OutboxWorker(
        db: db,
        remote: remote,
        isConnected: () async => true,
      );

  Future<void> seedFeed(List<Map<String, dynamic>> rows) async {
    for (final r in rows) {
      await syncEntityByName('prayer_feed')!.upsert(db, r);
    }
  }

  setUp(() {
    db = createTestDatabase();
    remote = FakeRemoteSource();
    repo = ModerationRepository(db);
  });
  tearDown(() => db.close());

  group('denúncia', () {
    test('entra no cache e na outbox só com os campos que o servidor aceita',
        () async {
      await seedFeed([_feedJson(id: 'p1', authorId: _other)]);

      final sent = await repo.reportPost(
        postId: 'p1',
        reporterId: _me,
        reason: ReportReason.spam,
      );
      expect(sent, isTrue);

      final row = await db.select(db.contentReportRows).getSingle();
      expect(row.postId, 'p1');
      expect(row.reason, 'spam');
      expect(row.resolvedAt, isNull);

      await worker().drain();
      final payload = remote.insertedPayloads['content_reports']!.single;
      // A cópia do post (post_title, post_body...) é o trigger do servidor
      // que preenche, da linha real. Mandá-la do app convidaria a forjar.
      expect(payload.keys.toSet(), {'id', 'reporter_id', 'post_id', 'reason'});
      expect(payload['reason'], 'spam');
      expect(await db.outboxEntries.count().getSingle(), 0);
    });

    test('segunda denúncia do mesmo post não sai do aparelho', () async {
      await seedFeed([_feedJson(id: 'p1', authorId: _other)]);
      await repo.reportPost(
        postId: 'p1',
        reporterId: _me,
        reason: ReportReason.spam,
      );

      final again = await repo.reportPost(
        postId: 'p1',
        reporterId: _me,
        reason: ReportReason.offensive,
      );

      // Sem a checagem local, ela iria otimista, voltaria 23505 do índice
      // único e seria revertida com mensagem de erro.
      expect(again, isFalse);
      expect(await db.outboxEntries.count().getSingle(), 1);
      expect(await db.contentReportRows.count().getSingle(), 1);
    });

    test('recusada pelo servidor, some do cache e o post volta ao feed',
        () async {
      await seedFeed([_feedJson(id: 'p1', authorId: _other)]);
      await repo.reportPost(
        postId: 'p1',
        reporterId: _me,
        reason: ReportReason.spam,
      );
      remote.insertErrors['content_reports'] = makeRlsException();

      await worker().drain();

      expect(await db.contentReportRows.count().getSingle(), 0);
      expect(await db.outboxEntries.count().getSingle(), 0);
    });

    test('resolver manda resolved_at e resolved_by, e tira da fila', () async {
      await syncEntityByName('content_reports')!.upsert(
        db,
        _reportJson(id: 'r1', reporterId: _other, postId: 'p1'),
      );

      await repo.resolveReport(reportId: 'r1', resolvedBy: _me);

      final row = await db.select(db.contentReportRows).getSingle();
      expect(row.resolvedAt, isNotNull);

      await worker().drain();
      final call = remote.calls.singleWhere((c) => c.method == 'update');
      expect(call.table, 'content_reports');
      expect(call.extra!['eqColumn'], 'id');
      expect(call.extra!['eqValue'], 'r1');
      expect(call.extra!['resolved_by'], _me);
      expect(call.extra!['resolved_at'], isNotNull);
    });

    test('pull reabre a denúncia quando o servidor manda resolved_at nulo',
        () async {
      // O motivo do Companion em `_upsertContentReport`: com a data class, o
      // upsert omitiria a coluna nula e o cache seguiria "resolvido".
      final entity = syncEntityByName('content_reports')!;
      await entity.upsert(
        db,
        _reportJson(
          id: 'r1',
          reporterId: _other,
          postId: 'p1',
          resolvedAt: DateTime.utc(2026, 9, 3),
        ),
      );
      await entity.upsert(
        db,
        _reportJson(id: 'r1', reporterId: _other, postId: 'p1'),
      );

      final row = await db.select(db.contentReportRows).getSingle();
      expect(row.resolvedAt, isNull);
    });
  });

  group('bloqueio', () {
    test('bloquear envia blocker_id e blocked_id', () async {
      await repo.blockUser(blockerId: _me, blockedId: _other);
      await repo.blockUser(blockerId: _me, blockedId: _other); // repetido

      expect(await db.userBlockRows.count().getSingle(), 1);
      expect(await db.outboxEntries.count().getSingle(), 1);

      await worker().drain();
      expect(remote.insertedPayloads['user_blocks']!.single, {
        'blocker_id': _me,
        'blocked_id': _other,
      });
    });

    test('desbloquear é DELETE físico filtrado por blocked_id', () async {
      await repo.blockUser(blockerId: _me, blockedId: _other);
      await worker().drain();

      await repo.unblockUser(_other);
      expect(await db.userBlockRows.count().getSingle(), 0);
      await worker().drain();

      // Não é soft delete: a tabela não tem `deleted_at`. E o filtro é por
      // `blocked_id` — o RLS restringe ao `blocker_id` de quem pede.
      final call = remote.calls.singleWhere((c) => c.method == 'delete');
      expect(call.table, 'user_blocks');
      expect(call.extra!['eqColumn'], 'blocked_id');
      expect(call.extra!['eqValue'], _other);
    });

    test('desbloqueio recusado devolve o bloqueio ao cache', () async {
      await repo.blockUser(blockerId: _me, blockedId: _other);
      await worker().drain();
      await repo.unblockUser(_other);
      remote.deleteResults['user_blocks'] = []; // 0 linhas

      await worker().drain();

      final rows = await db.select(db.userBlockRows).get();
      expect(rows.map((r) => r.blockedId), [_other]);
    });

    test('fullReplace tira do cache o bloqueio desfeito em outro aparelho',
        () async {
      final sync = SyncService(db: db, remote: remote);
      final entity = syncEntityByName('user_blocks')!;
      final ts = DateTime.utc(2026, 9, 1).toIso8601String();

      remote.fetchData['user_blocks'] = [
        {'blocker_id': _me, 'blocked_id': _other, 'created_at': ts},
        {'blocker_id': _me, 'blocked_id': _third, 'created_at': ts},
      ];
      await sync.pull(entity);
      expect(await db.userBlockRows.count().getSingle(), 2);

      remote.fetchData['user_blocks'] = [
        {'blocker_id': _me, 'blocked_id': _third, 'created_at': ts},
      ];
      await sync.pull(entity);

      final rows = await db.select(db.userBlockRows).get();
      expect(rows.map((r) => r.blockedId), [_third]);
    });
  });

  group('migration v6 -> v7', () {
    test('cria as duas tabelas no aparelho de quem já tinha o app', () async {
      // O aparelho na v6 não tem as tabelas de moderação.
      await db.customStatement('DROP TABLE content_report_rows');
      await db.customStatement('DROP TABLE user_block_rows');

      await db.migration.onUpgrade(Migrator(db), 6, 7);

      await repo.blockUser(blockerId: _me, blockedId: _other);
      await syncEntityByName('content_reports')!.upsert(
        db,
        _reportJson(id: 'r1', reporterId: _me, postId: 'p1'),
      );
      expect(await db.select(db.userBlockRows).get(), hasLength(1));
      expect(await db.select(db.contentReportRows).get(), hasLength(1));
    });
  });

  group('feed visível', () {
    late ProviderContainer container;

    ProviderContainer build() {
      final c = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(_me),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<List<String>> visibleIds() async {
      // Assina tudo antes de ler, para que as três streams tenham emitido.
      container.listen(visibleFeedProvider, (_, _) {});
      await container.read(prayerFeedProvider.future);
      await container.read(blockedUserIdsProvider.future);
      await container.read(reportedPostIdsProvider.future);
      await Future<void>.delayed(Duration.zero);
      return container.read(visibleFeedProvider).map((p) => p.id).toList();
    }

    setUp(() async {
      await seedFeed([
        _feedJson(id: 'mine', authorId: _me, title: 'meu'),
        _feedJson(id: 'other', authorId: _other, title: 'do outro'),
        _feedJson(id: 'third', authorId: _third, title: 'do terceiro'),
      ]);
      container = build();
    });

    test('esconde os posts de quem foi bloqueado, na hora', () async {
      await repo.blockUser(blockerId: _me, blockedId: _other);

      expect(await visibleIds(), unorderedEquals(['mine', 'third']));
    });

    test('esconde o post que a pessoa denunciou', () async {
      await repo.reportPost(
        postId: 'third',
        reporterId: _me,
        reason: ReportReason.other,
      );

      expect(await visibleIds(), unorderedEquals(['mine', 'other']));
    });

    test('denúncia feita por outra pessoa não esconde o post', () async {
      // O cache do admin tem as denúncias de todo mundo. Se o feed filtrasse
      // por elas, o admin perderia de vista justamente o que precisa moderar.
      await syncEntityByName('content_reports')!.upsert(
        db,
        _reportJson(id: 'r1', reporterId: _third, postId: 'other'),
      );

      expect(
        await visibleIds(),
        unorderedEquals(['mine', 'other', 'third']),
      );
    });
  });
}
