import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/app_role.dart';
import 'package:veredas/ui/screens/admin/membros_screen.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

// Administração dos membros.
//
// O bug que estes testes fixam: a seção "Pendentes de aprovação" no topo e a
// lista de baixo liam o mesmo `allProfilesProvider`, então cada pendente era
// desenhado duas vezes na mesma tela. É o tipo de erro que nenhum teste de
// provider pega — os dois provider estavam certos, quem errou foi a tela ao
// escolher qual deles usar.

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  Future<void> seedProfile({
    required String id,
    required String fullName,
    required bool isApproved,
    AppRole role = AppRole.obreiro,
  }) async {
    await db.into(db.profileRows).insert(
          ProfileRow(
            id: id,
            fullName: fullName,
            email: '$id@veredas.org',
            role: role,
            isApproved: isApproved,
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestWidgetWithRouter(
        initialLocation: '/admin/membros',
        child: const MembrosScreen(),
        db: db,
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

  testWidgets('um pendente aparece uma única vez na tela', (tester) async {
    await seedProfile(id: 'p1', fullName: 'Gabriel Souza', isApproved: false);
    await seedProfile(id: 'p2', fullName: 'Julia Fernandes', isApproved: true);

    await pumpScreen(tester);

    // Estava aparecendo duas vezes: na seção de pendentes e de novo na lista
    // completa logo abaixo.
    expect(find.text('Gabriel Souza'), findsOneWidget);
    expect(find.text('Julia Fernandes'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a busca continua encontrando quem está pendente',
      (tester) async {
    await seedProfile(id: 'p1', fullName: 'Gabriel Souza', isApproved: false);
    await seedProfile(id: 'p2', fullName: 'Julia Fernandes', isApproved: true);

    await pumpScreen(tester);

    // Tirar os pendentes da lista de baixo não pode torná-los inacessíveis: ao
    // buscar, a seção do topo some e a busca vale sobre todo mundo.
    await tester.enterText(find.byType(CupertinoSearchTextField), 'gabriel');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Gabriel Souza'), findsOneWidget);
    expect(find.text('Julia Fernandes'), findsNothing);

    await unmount(tester);
  });
}
