import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_colors.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';

import 'test_helpers.dart';

/// Cria uma árvore de widgets de teste que envolve [child] com tudo o que as
/// telas esperam: ProviderScope com overrides, CupertinoApp (não Material),
/// delegates de l10n, CupertinoTheme + AppTheme, e um GoRouter mínimo.
///
/// **Nunca use `tester.pumpAndSettle()`** com esta árvore: os StreamProviders
/// do drift nunca assentam. Use `tester.pump()` + `tester.pump(Duration(ms:50))`.
///
/// [additionalOverrides] para providers específicos da tela (ex.: repositórios).
/// Por padrão, sobrescreve apenas `appDatabaseProvider` e `authServiceProvider`.
Widget buildTestWidget({
  required Widget child,
  FakeAuthService? auth,
  AppDatabase? db,
  List<dynamic> additionalOverrides = const [],
}) {
  final testAuth = auth ?? FakeAuthService();
  final testDb = db ?? createTestDatabase();

  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWith((ref) {
        ref.onDispose(testDb.close);
        return testDb;
      }),
      authServiceProvider.overrideWithValue(testAuth),
      ...additionalOverrides,
    ],
    child: CupertinoApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      builder: (context, _) {
        return CupertinoTheme(
          data: cupertinoThemeFor(AppColors.light, Brightness.light),
          child: AppTheme(
            colors: AppColors.light,
            child: child,
          ),
        );
      },
    ),
  );
}

/// Cria um GoRouter de teste com [child] na rota inicial e uma rota dummy
/// em [destinationPath] para assertions de navegação.
GoRouter buildTestRouter({
  required String initialLocation,
  required Widget child,
  String destinationPath = '/destination',
  Widget destination = const SizedBox.shrink(),
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: initialLocation, builder: (_, _) => child),
      GoRoute(path: destinationPath, builder: (_, _) => destination),
    ],
  );
}

/// Envolve [child] com um GoRouter de teste dentro de uma CupertinoApp.
/// Combina [buildTestWidget] com [buildTestRouter] para telas que usam
/// `context.push`/`context.go`.
Widget buildTestWidgetWithRouter({
  required String initialLocation,
  required Widget child,
  FakeAuthService? auth,
  AppDatabase? db,
  List<dynamic> additionalOverrides = const [],
  String destinationPath = '/destination',
  Widget destination = const SizedBox.shrink(),
}) {
  final router = buildTestRouter(
    initialLocation: initialLocation,
    child: child,
    destinationPath: destinationPath,
    destination: destination,
  );

  final testAuth = auth ?? FakeAuthService();
  final testDb = db ?? createTestDatabase();

  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWith((ref) {
        ref.onDispose(testDb.close);
        return testDb;
      }),
      authServiceProvider.overrideWithValue(testAuth),
      ...additionalOverrides,
    ],
    child: CupertinoApp.router(
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return CupertinoTheme(
          data: cupertinoThemeFor(AppColors.light, Brightness.light),
          child: AppTheme(
            colors: AppColors.light,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    ),
  );
}
