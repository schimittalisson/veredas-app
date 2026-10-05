import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_colors.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/root_scaffold.dart';

import '../helpers/test_helpers.dart';

// O aluno da ETED vê quatro abas: a do mural sai. O shell continua com cinco
// branches, então a barra precisa traduzir a posição do botão para o branch —
// o risco é o botão "Arquivos", agora o 4º, abrir o branch 3 (o mural).

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());

  Future<void> pumpShell(WidgetTester tester, {required bool student}) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/inicio',
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
                  GoRoute(
                    path: path,
                    builder: (_, _) => Center(child: Text('página $path')),
                  ),
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
          isStudentProvider.overrideWithValue(student),
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

  testWidgets('aluno: quatro abas, sem Oração, e Arquivos abre Arquivos',
      (tester) async {
    await pumpShell(tester, student: true);

    expect(find.text('Oração'), findsNothing);
    expect(find.text('Arquivos'), findsOneWidget);

    await tester.tap(find.text('Arquivos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('página /arquivos'), findsOneWidget);
    expect(find.text('página /oracao'), findsNothing);

    await unmount(tester);
  });

  testWidgets('obreiro: cinco abas, com Oração', (tester) async {
    await pumpShell(tester, student: false);

    expect(find.text('Oração'), findsOneWidget);

    await tester.tap(find.text('Oração'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('página /oracao'), findsOneWidget);

    await unmount(tester);
  });
}
