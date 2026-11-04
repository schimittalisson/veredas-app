import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/screens/prayer/prayer_detail_screen.dart';
import 'package:veredas/ui/screens/prayer/prayer_wall_screen.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

// Comentar numa oração. O cartão mostrava "0 comentários" e o toque não fazia
// nada; agora abre o detalhe, onde se lê, comenta, apaga e denuncia.

const _me = 'u-me';
const _other = 'u-other';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = createTestDatabase();
    final ts = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    await db.into(db.prayerFeedRows).insert(
          PrayerFeedRow(
            id: 'p1',
            authorId: _other,
            title: 'Viagem missionária',
            body: 'Corpo do pedido',
            isAnonymous: false,
            authorName: 'Bia',
            prayingCount: 0,
            commentCount: 0,
            isPraying: false,
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    for (final (id, name) in [(_me, 'Eu Mesmo'), (_other, 'Bia Souza')]) {
      await db.into(db.profileRows).insert(
            ProfileRowsCompanion.insert(
              id: id,
              fullName: name,
              role: AppRole.obreiro,
              updatedAt: ts,
            ),
          );
    }
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool isAdmin = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        initialLocation: '/oracao',
        child: child,
        db: db,
        destinationPath: '/oracao/detalhe',
        destination: const PrayerDetailScreen(postId: 'p1'),
        additionalOverrides: [
          currentUserIdProvider.overrideWithValue(_me),
          isAdminProvider.overrideWithValue(isAdmin),
        ],
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4)); // timer do toast
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<void> addComment(String id, String authorId, String body) async {
    final ts = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
    await db.into(db.prayerCommentRows).insert(
          PrayerCommentRow(
            id: id,
            postId: 'p1',
            authorId: authorId,
            body: body,
            createdAt: ts,
            updatedAt: ts,
          ),
        );
  }

  testWidgets('o contador do cartão abre os comentários', (tester) async {
    await addComment('c1', _other, 'Estou junto!');
    await pump(
      tester,
      CupertinoPageScaffold(
        child: ListView(
          children: [
            PrayerCard(
              post: await db.select(db.prayerFeedRows).getSingle(),
            ),
          ],
        ),
      ),
    );

    // A contagem vem do cache local, não do comment_count da view (0).
    expect(find.text('1 comentário'), findsOneWidget);

    await tester.tap(find.text('1 comentário'));
    await settle(tester);

    expect(find.byType(PrayerDetailScreen), findsOneWidget);
    expect(find.text('Estou junto!'), findsOneWidget);
    expect(find.textContaining('Bia Souza'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('escrever e enviar põe o comentário na lista', (tester) async {
    await pump(tester, const PrayerDetailScreen(postId: 'p1'));
    expect(find.text('Nenhum comentário ainda.'), findsOneWidget);

    final send = find.widgetWithText(CupertinoButton, 'Enviar');
    // Vazio não envia.
    expect(tester.widget<CupertinoButton>(send).onPressed, isNull);

    await tester.enterText(find.byType(CupertinoTextField), '  Orando!  ');
    await tester.pump();
    await tester.tap(send);
    await settle(tester);

    expect(find.text('Orando!'), findsOneWidget);
    expect(find.text('Nenhum comentário ainda.'), findsNothing);
    final row = await db.select(db.prayerCommentRows).getSingle();
    expect(row.body, 'Orando!');
    expect(row.authorId, _me);
    expect(await db.outboxEntries.count().getSingle(), 1);

    await unmount(tester);
  });

  testWidgets('no comentário alheio: denunciar e bloquear, sem excluir',
      (tester) async {
    await addComment('c1', _other, 'Comentário dela');
    await pump(tester, const PrayerDetailScreen(postId: 'p1'));

    final tile = find.ancestor(
      of: find.text('Comentário dela'),
      matching: find.byType(Row),
    ).first;
    await tester.tap(
      find.descendant(of: tile, matching: find.byIcon(CupertinoIcons.ellipsis)),
    );
    await settle(tester);

    expect(find.text('Denunciar'), findsOneWidget);
    expect(find.text('Bloquear Bia Souza'), findsOneWidget);
    expect(find.text('Excluir'), findsNothing);

    // Denunciar tira o comentário da tela de quem denunciou.
    await tester.tap(find.text('Denunciar'));
    await settle(tester);
    await tester.tap(find.text('Spam ou propaganda'));
    await settle(tester);

    expect(find.text('Comentário dela'), findsNothing);
    final report = await db.select(db.contentReportRows).getSingle();
    expect(report.commentId, 'c1');

    await unmount(tester);
  });

  testWidgets('no próprio comentário: excluir, sem denunciar', (tester) async {
    await addComment('c1', _me, 'Meu comentário');
    await pump(tester, const PrayerDetailScreen(postId: 'p1'));

    final tile = find.ancestor(
      of: find.text('Meu comentário'),
      matching: find.byType(Row),
    ).first;
    await tester.tap(
      find.descendant(of: tile, matching: find.byIcon(CupertinoIcons.ellipsis)),
    );
    await settle(tester);

    expect(find.text('Denunciar'), findsNothing);
    await tester.tap(find.text('Excluir'));
    await settle(tester);
    expect(find.text('Excluir este comentário?'), findsOneWidget);
    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Excluir'));
    await settle(tester);

    expect(find.text('Meu comentário'), findsNothing);
    expect(await db.prayerCommentRows.count().getSingle(), 0);

    await unmount(tester);
  });

  testWidgets('admin pode excluir o comentário alheio', (tester) async {
    await addComment('c1', _other, 'Comentário dela');
    await pump(tester, const PrayerDetailScreen(postId: 'p1'), isAdmin: true);

    final tile = find.ancestor(
      of: find.text('Comentário dela'),
      matching: find.byType(Row),
    ).first;
    await tester.tap(
      find.descendant(of: tile, matching: find.byIcon(CupertinoIcons.ellipsis)),
    );
    await settle(tester);

    expect(find.text('Excluir'), findsOneWidget);
    expect(find.text('Denunciar'), findsOneWidget);

    await unmount(tester);
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
