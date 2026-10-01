import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_colors.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/root_scaffold.dart';

import '../helpers/test_helpers.dart';

// O bug: tocar na busca do mural fazia a tela inteira sumir — busca, campo
// "compartilhe sua oração" e lista — enquanto o teclado estivesse aberto.
//
// A casca das abas encolhia pelo teclado e, ao montar o MediaQuery com o
// espaço da barra flutuante, repassava o `viewInsets` original para a tela da
// aba, que encolhia de novo. Teclado descontado duas vezes: a altura que
// sobrava ficava negativa. Valia para qualquer campo de texto dentro das abas.

/// Uma tela de aba com a mesma estrutura do mural: barra de navegação, campo
/// no topo e uma lista que ocupa o resto.
class _TabPage extends StatelessWidget {
  const _TabPage();

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Oração')),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(
              height: 44,
              child: Center(child: Text('campo de busca')),
            ),
            Expanded(
              child: ListView(children: const [Text('primeira oração')]),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());

  Future<void> pumpShell(WidgetTester tester) async {
    // iPhone de 393x852 pt, com a área segura de cima e de baixo.
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/oracao',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              RootScaffold(navigationShell: shell),
          branches: [
            for (final path in [
              '/inicio',
              '/agenda',
              '/escalas',
              '/oracao',
              '/arquivos',
            ])
              StatefulShellBranch(
                routes: [
                  GoRoute(path: path, builder: (_, _) => const _TabPage()),
                ],
              ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          remoteSourceProvider.overrideWithValue(FakeRemoteSource()),
          connectivityMonitorProvider
              .overrideWithValue(FakeConnectivityMonitor()),
          isOnlineProvider.overrideWithValue(true),
        ],
        child: CupertinoApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => AppTheme(
            colors: AppColors.light,
            child: child!,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('com o teclado aberto, o topo da aba continua na tela',
      (tester) async {
    await pumpShell(tester);
    expect(find.text('campo de busca'), findsOneWidget);
    expect(find.text('primeira oração'), findsOneWidget);

    // Teclado do iPhone: ~336 pt. Com ele aberto o sistema zera o padding de
    // baixo (o teclado cobre o indicador de início).
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    tester.view.padding = const FakeViewPadding(top: 59);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Sobram 852 - 59 - 336 = 457 pt, menos a barra de navegação: cabe o
    // campo e o começo da lista. Com o teclado descontado duas vezes, a
    // altura ficava negativa e nada era desenhado.
    expect(find.text('campo de busca').hitTestable(), findsOneWidget);
    expect(find.text('primeira oração').hitTestable(), findsOneWidget);

    await unmount(tester);
  });

  test('a barra flutuante só reserva espaço com o teclado fechado', () {
    const closed = MediaQueryData(padding: EdgeInsets.only(bottom: 34));
    const open = MediaQueryData(viewInsets: EdgeInsets.only(bottom: 336));

    expect(rootContentMediaQuery(closed).padding.bottom, greaterThan(34));
    // Com o teclado, a barra fica atrás dele: nada a reservar por cima.
    expect(rootContentMediaQuery(open).padding.bottom, 0);
    // E o teclado passa intacto para a aba, que encolhe por ele uma vez.
    expect(rootContentMediaQuery(open).viewInsets.bottom, 336);
  });
}
