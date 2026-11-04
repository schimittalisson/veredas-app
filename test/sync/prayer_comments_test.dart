import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/report_reason.dart';
import 'package:veredas/data/repositories/moderation_repository.dart';
import 'package:veredas/data/repositories/prayer_repository.dart';
import 'package:veredas/data/sync/outbox_worker.dart';
import 'package:veredas/data/sync/sync_entity.dart';
import 'package:veredas/data/sync/sync_service.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/prayer_providers.dart';

import '../helpers/test_helpers.dart';

// Comentários no mural. O cartão da oração mostrava "0 comentários" desde a
// Fase 8 e não havia como comentar; a tabela e o sync existiam, a escrita e a
// tela não.

const _me = 'u-me';
const _other = 'u-other';

Map<String, dynamic> _feedJson(String id, {String authorId = _other}) {
  final ts = DateTime.utc(2026, 9, 1).toIso8601String();
  return {
    'id': id,
    'author_id': authorId,
    'title': 'Pedido $id',
    'body': 'Corpo',
    'is_anonymous': false,
    'answered_at': null,
    'answer_note': null,
    'author_name': 'Autor',
    'author_avatar_url': null,
    'praying_count': 0,
    'comment_count': 0,
    'is_praying': false,
    'created_at': ts,
    'updated_at': ts,
  };
}

Map<String, dynamic> _commentJson(
  String id, {
  String postId = 'p1',
  String authorId = _other,
  int minute = 0,
}) {
  final ts = DateTime.utc(2026, 9, 2, 10, minute).toIso8601String();
  return {
    'id': id,
    'post_id': postId,
    'author_id': authorId,
    'body': 'Comentário $id',
    'created_at': ts,
    'updated_at': ts,
    'deleted_at': null,
  };
}

void main() {
  late AppDatabase db;
  late FakeRemoteSource remote;
  late PrayerRepository prayers;
  late ModerationRepository moderation;

  OutboxWorker worker() => OutboxWorker(
        db: db,
        remote: remote,
        isConnected: () async => true,
      );

  Future<void> seedFeed(String id) =>
      syncEntityByName('prayer_feed')!.upsert(db, _feedJson(id));

  Future<void> seedComment(Map<String, dynamic> json) =>
      syncEntityByName('prayer_comments')!.upsert(db, json);

  setUp(() async {
    db = createTestDatabase();
    remote = FakeRemoteSource();
    prayers = PrayerRepository(db);
    moderation = ModerationRepository(db);
    await seedFeed('p1');
  });
  tearDown(() => db.close());

  group('escrita', () {
    test('comentar aparece no cache e sai pela outbox', () async {
      await prayers.addComment(postId: 'p1', authorId: _me, body: 'Amém');

      final row = await db.select(db.prayerCommentRows).getSingle();
      expect(row.postId, 'p1');
      expect(row.authorId, _me);
      expect(row.body, 'Amém');

      await worker().drain();
      final payload = remote.insertedPayloads['prayer_comments']!.single;
      expect(payload, {
        'id': row.id,
        'post_id': 'p1',
        'author_id': _me,
        'body': 'Amém',
      });
      expect(await db.outboxEntries.count().getSingle(), 0);
    });

    test('comentário recusado pelo servidor some do cache', () async {
      await prayers.addComment(postId: 'p1', authorId: _me, body: 'Amém');
      remote.insertErrors['prayer_comments'] = makeRlsException();

      await worker().drain();

      expect(await db.prayerCommentRows.count().getSingle(), 0);
    });

    test('apagar é soft delete com RETURNING na tabela de comentários',
        () async {
      await seedComment(_commentJson('c1', authorId: _me));

      await prayers.deleteComment('c1');
      expect(await db.prayerCommentRows.count().getSingle(), 0);

      await worker().drain();
      final call = remote.calls.singleWhere((c) => c.method == 'update');
      expect(call.table, 'prayer_comments');
      expect(call.extra!['eqValue'], 'c1');
      expect(call.extra!['deleted_at'], isNotNull);
    });

    test('exclusão negada em silêncio (0 linhas) devolve o comentário',
        () async {
      // É o caso que o RETURNING reprovava antes da migration
      // 20261104000100, e que o 0-linhas cobre quando a policy nega pelo USING.
      await seedComment(_commentJson('c1'));
      await prayers.deleteComment('c1');
      remote.updateResults['prayer_comments'] = [];

      await worker().drain();

      final rows = await db.select(db.prayerCommentRows).get();
      expect(rows.map((r) => r.id), ['c1']);
    });

    test('lápide vinda do pull não entra no cache', () async {
      await seedComment(_commentJson('c1'));
      remote.fetchData['prayer_comments'] = [
        {..._commentJson('c1'), 'deleted_at': '2026-09-03T00:00:00Z'},
      ];

      await SyncService(db: db, remote: remote)
          .pull(syncEntityByName('prayer_comments')!);

      expect(await db.prayerCommentRows.count().getSingle(), 0);
    });
  });

  group('denúncia de comentário', () {
    test('manda comment_id e o post do comentário, e não repete', () async {
      await seedComment(_commentJson('c1'));

      final sent = await moderation.reportComment(
        commentId: 'c1',
        reporterId: _me,
        reason: ReportReason.offensive,
      );
      final again = await moderation.reportComment(
        commentId: 'c1',
        reporterId: _me,
        reason: ReportReason.spam,
      );
      expect(sent, isTrue);
      expect(again, isFalse);

      final row = await db.select(db.contentReportRows).getSingle();
      expect(row.commentId, 'c1');
      expect(row.postId, 'p1');
      expect(row.commentBody, 'Comentário c1');
      expect(row.commentAuthorId, _other);

      await worker().drain();
      final payload = remote.insertedPayloads['content_reports']!.single;
      // A cópia do comentário é o trigger do servidor que tira.
      expect(
        payload.keys.toSet(),
        {'id', 'reporter_id', 'post_id', 'comment_id', 'reason'},
      );
    });

    test('denunciar o comentário não impede denunciar o post', () async {
      await seedComment(_commentJson('c1'));
      await moderation.reportComment(
        commentId: 'c1',
        reporterId: _me,
        reason: ReportReason.offensive,
      );

      final postReport = await moderation.reportPost(
        postId: 'p1',
        reporterId: _me,
        reason: ReportReason.spam,
      );

      expect(postReport, isTrue);
      expect(await db.contentReportRows.count().getSingle(), 2);
    });

    test('pull grava os campos do comentário', () async {
      final ts = DateTime.utc(2026, 9, 2).toIso8601String();
      await syncEntityByName('content_reports')!.upsert(db, {
        'id': 'r1',
        'reporter_id': _me,
        'post_id': 'p1',
        'comment_id': 'c1',
        'comment_body': 'texto denunciado',
        'comment_author_id': _other,
        'reason': 'offensive',
        'post_title': 'Pedido',
        'post_body': 'Corpo',
        'post_author_id': _other,
        'post_is_anonymous': false,
        'resolved_at': null,
        'created_at': ts,
        'updated_at': ts,
      });

      final row = await db.select(db.contentReportRows).getSingle();
      expect(row.commentId, 'c1');
      expect(row.commentBody, 'texto denunciado');
      expect(row.commentAuthorId, _other);
    });
  });

  group('o que a pessoa vê', () {
    ProviderContainer container({bool isAdmin = false}) {
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          currentUserIdProvider.overrideWithValue(_me),
          isAdminProvider.overrideWithValue(isAdmin),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    /// Mantém os providers vivos e espera as streams do drift assentarem.
    Future<void> settle(ProviderContainer c) async {
      c.listen(visibleFeedProvider, (_, _) {});
      c.listen(visibleCommentsProvider('p1'), (_, _) {});
      c.listen(commentCountsProvider, (_, _) {});
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('comentários em ordem de conversa, com a contagem', () async {
      await seedComment(_commentJson('c2', minute: 5));
      await seedComment(_commentJson('c1', minute: 1));
      final c = container();
      await settle(c);

      expect(
        c.read(visibleCommentsProvider('p1')).map((x) => x.row.id),
        ['c1', 'c2'],
      );
      expect(c.read(commentCountsProvider)['p1'], 2);
    });

    test('bloquear o autor esconde o comentário e tira da contagem', () async {
      await seedComment(_commentJson('c1'));
      await seedComment(_commentJson('c2', authorId: _me));
      final c = container();
      await settle(c);

      await moderation.blockUser(blockerId: _me, blockedId: _other);
      await settle(c);

      expect(
        c.read(visibleCommentsProvider('p1')).map((x) => x.row.id),
        ['c2'],
      );
      expect(c.read(commentCountsProvider)['p1'], 1);
    });

    test('denunciar o comentário o esconde, mas não esconde a oração',
        () async {
      // A denúncia de comentário também carrega `post_id`. Sem o filtro por
      // `comment_id` em `watchReportedPostIds`, a oração inteira sumiria.
      await seedComment(_commentJson('c1'));
      final c = container();
      await settle(c);

      await moderation.reportComment(
        commentId: 'c1',
        reporterId: _me,
        reason: ReportReason.offensive,
      );
      await settle(c);

      expect(c.read(visibleCommentsProvider('p1')), isEmpty);
      expect(c.read(visibleFeedProvider).map((p) => p.id), ['p1']);
    });

    test('para o admin, a própria denúncia não esconde o comentário',
        () async {
      await seedComment(_commentJson('c1'));
      final c = container(isAdmin: true);
      await settle(c);

      await moderation.reportComment(
        commentId: 'c1',
        reporterId: _me,
        reason: ReportReason.offensive,
      );
      await settle(c);

      expect(c.read(visibleCommentsProvider('p1')), hasLength(1));
    });
  });

  group('migration v8 -> v9', () {
    test('denúncias antigas continuam, como denúncias de post', () async {
      await db.customStatement(
        'ALTER TABLE content_report_rows DROP COLUMN comment_id',
      );
      await db.customStatement(
        'ALTER TABLE content_report_rows DROP COLUMN comment_body',
      );
      await db.customStatement(
        'ALTER TABLE content_report_rows DROP COLUMN comment_author_id',
      );
      await db.customStatement(
        "INSERT INTO content_report_rows (id, reporter_id, post_id, reason, "
        "post_is_anonymous, created_at, updated_at) "
        "VALUES ('r1', 'u-me', 'p1', 'spam', 0, 0, 0)",
      );

      await db.migration.onUpgrade(Migrator(db), 8, 9);

      final row = await db.select(db.contentReportRows).getSingle();
      expect(row.id, 'r1');
      expect(row.commentId, isNull);
    });
  });
}
