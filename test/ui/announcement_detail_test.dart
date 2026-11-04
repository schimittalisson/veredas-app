import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/screens/home/announcement_detail_screen.dart';
import 'package:veredas/ui/screens/home/home_screen.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

// Tocar num aviso da lista "Avisos" não fazia nada: o texto aparecia cortado
// em duas linhas e o admin não tinha como editar um aviso não fixado.

const _longBody = 'Linha um do aviso.\nLinha dois.\nLinha três.\n'
    'Linha quatro, que a célula da lista nunca mostra.';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = createTestDatabase();
    await db.into(db.announcementRows).insert(
          AnnouncementRow(
            id: 'a1',
            title: 'Mutirão no sábado',
            body: _longBody,
            pinned: false,
            authorName: 'Ana',
            createdAt: DateTime.utc(2026, 9, 20),
            updatedAt: DateTime.utc(2026, 9, 20),
          ),
        );
  });

  Future<void> pump(WidgetTester tester, Widget child,
      {required bool isAdmin}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        initialLocation: '/inicio',
        child: child,
        db: db,
        destinationPath: '/aviso',
        destination: const AnnouncementDetailScreen(announcementId: 'a1'),
        additionalOverrides: [isAdminProvider.overrideWithValue(isAdmin)],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('tocar no aviso da lista abre o texto inteiro', (tester) async {
    await pump(tester, const HomeScreen(), isAdmin: false);

    await tester.tap(find.text('Mutirão no sábado'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AnnouncementDetailScreen), findsOneWidget);
    expect(find.text(_longBody), findsOneWidget);
    // Obreiro lê, mas não edita nem exclui.
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Excluir'), findsNothing);

    await unmount(tester);
  });

  testWidgets('admin vê editar e excluir no detalhe', (tester) async {
    await pump(
      tester,
      const AnnouncementDetailScreen(announcementId: 'a1'),
      isAdmin: true,
    );

    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Excluir'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('aviso que sumiu do cache mostra o estado vazio', (tester) async {
    await (db.delete(db.announcementRows)).go();
    await pump(
      tester,
      const AnnouncementDetailScreen(announcementId: 'a1'),
      isAdmin: true,
    );

    expect(find.text('Este aviso foi removido.'), findsOneWidget);
    expect(find.text('Editar'), findsNothing);

    await unmount(tester);
  });
}
