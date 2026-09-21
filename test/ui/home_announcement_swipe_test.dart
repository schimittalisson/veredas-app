import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/screens/home/home_screen.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

// Excluir aviso arrastando a célula para a esquerda.
//
// O que só um teste de widget pega aqui: o `confirmDismiss` devolve `false`
// mesmo quando exclui. Se alguém "consertar" isso para `true` — que é o que
// parece certo lendo a API —, o Dismissible tira a célula da árvore por conta
// própria, a lista (que vem de um StreamProvider do drift) ainda não emitiu, e
// o Flutter lança "A dismissed Dismissible widget is still part of the tree".
// O erro não aparece na leitura do código e some em um teste que só confira o
// banco.

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  Future<void> seedAnnouncement({
    required String id,
    required String title,
    bool pinned = false,
  }) async {
    await db.into(db.announcementRows).insert(
          AnnouncementRow(
            id: id,
            title: title,
            body: 'Corpo do $title',
            pinned: pinned,
            createdAt: DateTime.utc(2026, 9, 20),
            updatedAt: DateTime.utc(2026, 9, 20),
          ),
        );
  }

  Future<void> pumpHome(WidgetTester tester, {required bool isAdmin}) async {
    // A janela padrão do flutter_test é 800x600 e a tela Início é longa: a
    // seção de avisos cai fora da viewport, e o que está fora não recebe
    // toque nem arrasto. Uma tela de celular de verdade cabe.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        initialLocation: '/inicio',
        child: const HomeScreen(),
        db: db,
        additionalOverrides: [
          isAdminProvider.overrideWithValue(isAdmin),
        ],
      ),
    );
    // Nunca pumpAndSettle: os StreamProviders do drift não assentam.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Ver a nota em `scale_tab_view_test.dart`: sem desmontar aqui, o timer que
  /// o drift agenda ao cancelar o stream vaza para fora do teste.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  /// Arrasta a célula para a esquerda o bastante para passar do limiar do
  /// Dismissible (40% da largura por padrão).
  Future<void> swipeLeft(WidgetTester tester, String title) async {
    await tester.drag(find.text(title), const Offset(-500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<List<String>> remainingIds() async {
    final rows = await db.select(db.announcementRows).get();
    return rows.map((r) => r.id).toList()..sort();
  }

  testWidgets('admin arrasta, confirma e o aviso sai da lista', (tester) async {
    await seedAnnouncement(id: 'a1', title: 'Mutirão no sábado');
    await seedAnnouncement(id: 'a2', title: 'Reunião de equipe');

    await pumpHome(tester, isAdmin: true);
    expect(find.text('Mutirão no sábado'), findsOneWidget);

    await swipeLeft(tester, 'Mutirão no sábado');

    // O arrasto não exclui sozinho: pergunta antes.
    expect(find.text('Excluir este aviso?'), findsOneWidget);
    expect(await remainingIds(), ['a1', 'a2']);

    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Excluir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(await remainingIds(), ['a2']);
    expect(find.text('Mutirão no sábado'), findsNothing);
    expect(find.text('Reunião de equipe'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('cancelar no diálogo devolve a célula ao lugar', (tester) async {
    await seedAnnouncement(id: 'a1', title: 'Mutirão no sábado');

    await pumpHome(tester, isAdmin: true);
    await swipeLeft(tester, 'Mutirão no sábado');

    await tester.tap(find.widgetWithText(CupertinoDialogAction, 'Cancelar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // A célula volta inteira: o `confirmDismiss` false desfaz o arrasto.
    expect(await remainingIds(), ['a1']);
    expect(find.text('Mutirão no sábado'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('obreiro comum nao tem o gesto', (tester) async {
    await seedAnnouncement(id: 'a1', title: 'Mutirão no sábado');

    await pumpHome(tester, isAdmin: false);

    expect(find.byType(Dismissible), findsNothing);

    await swipeLeft(tester, 'Mutirão no sábado');

    expect(find.text('Excluir este aviso?'), findsNothing);
    expect(await remainingIds(), ['a1']);

    await unmount(tester);
  });

  testWidgets('o aviso fixado nao ganha o gesto (tem o menu)', (tester) async {
    // O fixado é uma faixa de destaque, não célula de lista: quem exclui lá é
    // o menu de reticências. Um Dismissible ali arrastaria o banner inteiro.
    await seedAnnouncement(id: 'a1', title: 'Aviso fixado', pinned: true);
    await seedAnnouncement(id: 'a2', title: 'Reunião de equipe');

    await pumpHome(tester, isAdmin: true);

    expect(find.byType(Dismissible), findsOneWidget);

    await unmount(tester);
  });
}
