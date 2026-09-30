import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/prayer_providers.dart';
import 'package:veredas/ui/screens/prayer/prayer_wall_screen.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

// Denunciar e bloquear pelo menu do cartão do mural (App Store, 1.2).
//
// Os testes passam pelo filtro real do feed (`filteredFeedProvider`): é ele
// que tira o cartão da tela, e o que a pessoa vê é o post sumir e o aviso
// aparecer. O cartão captura overlay e repositório antes do `await` porque a
// ordem entre a volta da escrita e a emissão do stream do drift não é
// garantida — neste ambiente o await volta primeiro, então estes testes NÃO
// provam que a captura é necessária, só que o fluxo funciona com ela.

const _me = 'u-me';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  Future<void> seedPost({
    required String id,
    required String authorId,
    required String title,
    String? authorName,
    bool isAnonymous = false,
    required int minutesAgo,
  }) async {
    final ts = DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo));
    await db.into(db.prayerFeedRows).insert(
          PrayerFeedRow(
            id: id,
            authorId: authorId,
            title: title,
            body: 'Corpo de $title',
            isAnonymous: isAnonymous,
            authorName: isAnonymous ? null : authorName,
            prayingCount: 0,
            commentCount: 0,
            isPraying: false,
            createdAt: ts,
            updatedAt: ts,
          ),
        );
  }

  Future<void> pumpFeed(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Um feed mínimo sobre o provider real: é o filtro dele que desmonta o
    // cartão, e é isso que o teste precisa exercitar. A tela inteira puxaria
    // o controle de sincronização junto, que não interessa aqui.
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        initialLocation: '/oracao',
        db: db,
        additionalOverrides: [
          currentUserIdProvider.overrideWithValue(_me),
          isAdminProvider.overrideWithValue(false),
        ],
        child: CupertinoPageScaffold(
          child: Consumer(
            builder: (context, ref, _) {
              final feed = ref.watch(filteredFeedProvider);
              return ListView(
                children: [for (final p in feed) PrayerCard(post: p)],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> unmount(WidgetTester tester) async {
    // O toast agenda um timer de 3 s; deixa-o vencer antes de desmontar.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<void> openMenu(WidgetTester tester, String title) async {
    final card = find.ancestor(
      of: find.text(title),
      matching: find.byType(PrayerCard),
    );
    await tester.tap(
      find.descendant(of: card, matching: find.byIcon(CupertinoIcons.ellipsis)),
    );
    await settle(tester);
  }

  testWidgets('menu: denunciar e bloquear no post alheio, nada disso no meu',
      (tester) async {
    await seedPost(
      id: 'mine',
      authorId: _me,
      authorName: 'Eu',
      title: 'Meu pedido',
      minutesAgo: 1,
    );
    await seedPost(
      id: 'ana',
      authorId: 'u-ana',
      authorName: 'Ana Souza',
      title: 'Pedido da Ana',
      minutesAgo: 2,
    );
    await seedPost(
      id: 'anon',
      authorId: 'u-anon',
      isAnonymous: true,
      title: 'Pedido anônimo',
      minutesAgo: 3,
    );
    await pumpFeed(tester);

    await openMenu(tester, 'Pedido da Ana');
    expect(find.text('Denunciar'), findsOneWidget);
    expect(find.text('Bloquear Ana Souza'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);

    // Anônimo: denuncia, mas não bloqueia — a lista de bloqueados revelaria
    // quem escreveu.
    await openMenu(tester, 'Pedido anônimo');
    expect(find.text('Denunciar'), findsOneWidget);
    expect(find.textContaining('Bloquear'), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);

    await openMenu(tester, 'Meu pedido');
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Denunciar'), findsNothing);
    expect(find.textContaining('Bloquear'), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);

    await unmount(tester);
  });

  testWidgets('denunciar tira o post do feed e confirma com um aviso',
      (tester) async {
    await seedPost(
      id: 'ana',
      authorId: 'u-ana',
      authorName: 'Ana Souza',
      title: 'Pedido da Ana',
      minutesAgo: 2,
    );
    await pumpFeed(tester);

    await openMenu(tester, 'Pedido da Ana');
    await tester.tap(find.text('Denunciar'));
    await settle(tester);

    expect(
      find.text('Por que você está denunciando este pedido?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Spam ou propaganda'));
    await settle(tester);

    expect(find.text('Pedido da Ana'), findsNothing);
    expect(
      find.text('Denúncia enviada. Este pedido não aparece mais para você.'),
      findsOneWidget,
    );
    final report = await db.select(db.contentReportRows).getSingle();
    expect(report.postId, 'ana');
    expect(report.reason, 'spam');
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });

  testWidgets('bloquear pede confirmação e some com todos os posts da pessoa',
      (tester) async {
    await seedPost(
      id: 'ana1',
      authorId: 'u-ana',
      authorName: 'Ana Souza',
      title: 'Primeiro da Ana',
      minutesAgo: 2,
    );
    await seedPost(
      id: 'ana2',
      authorId: 'u-ana',
      authorName: 'Ana Souza',
      title: 'Segundo da Ana',
      minutesAgo: 3,
    );
    await seedPost(
      id: 'beto',
      authorId: 'u-beto',
      authorName: 'Beto Lima',
      title: 'Pedido do Beto',
      minutesAgo: 4,
    );
    await pumpFeed(tester);

    await openMenu(tester, 'Primeiro da Ana');
    await tester.tap(find.text('Bloquear Ana Souza'));
    await settle(tester);

    expect(find.text('Bloquear Ana Souza?'), findsOneWidget);
    expect(await db.select(db.userBlockRows).get(), isEmpty);

    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Bloquear'));
    await settle(tester);

    expect(find.text('Primeiro da Ana'), findsNothing);
    expect(find.text('Segundo da Ana'), findsNothing);
    expect(find.text('Pedido do Beto'), findsOneWidget);
    expect(
      find.text(
        'Bloqueio feito. Os pedidos dessa pessoa não aparecem mais para você.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });
}
