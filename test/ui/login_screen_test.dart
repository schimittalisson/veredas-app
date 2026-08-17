import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/core/theme/app_colors.dart';
import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/screens/auth/login_screen.dart';

import '../helpers/test_helpers.dart';
import '../helpers/widget_test_helpers.dart';

void main() {
  group('LoginScreen', () {
    testWidgets('exibe logo, subtítulo, campos e botão de entrar',
        (tester) async {
      await tester.pumpWidget(
        buildTestWidgetWithRouter(
          initialLocation: '/login',
          child: const LoginScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // O subtítulo "JOCUM Veredas App" aparece como texto.
      expect(find.text('JOCUM Veredas App'), findsOneWidget);
      // Placeholder do e-mail.
      expect(find.text('E-mail'), findsOneWidget);
      // Placeholder da senha.
      expect(find.text('Senha'), findsOneWidget);
      // Botão de entrar.
      expect(find.text('Entrar'), findsWidgets);
      // Link de esqueci minha senha.
      expect(find.text('Esqueci minha senha'), findsOneWidget);
      // Link de criar conta.
      expect(find.text('Criar conta'), findsOneWidget);
    });

    testWidgets('valida e-mail vazio e não tenta login', (tester) async {
      final auth = FakeAuthService();

      await tester.pumpWidget(
        buildTestWidgetWithRouter(
          initialLocation: '/login',
          child: const LoginScreen(),
          auth: auth,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Tenta submeter sem preencher nada.
      await tester.tap(find.text('Entrar').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Deve mostrar mensagem de validação.
      expect(find.text('Dados inválidos. Verifique os campos.'),
          findsAtLeast(1));
      // Não deve ter chamado signIn.
      expect(auth.calls.where((c) => c.startsWith('signIn')), isEmpty);
    });

    testWidgets('chama signIn com credenciais válidas', (tester) async {
      final auth = FakeAuthService();

      await tester.pumpWidget(
        buildTestWidgetWithRouter(
          initialLocation: '/login',
          child: const LoginScreen(),
          auth: auth,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Preenche e-mail.
      await tester.enterText(find.byType(CupertinoTextFormFieldRow).at(0),
          'test@veredas.org');
      // Preenche senha.
      await tester.enterText(find.byType(CupertinoTextFormFieldRow).at(1),
          'password123');
      await tester.pump();

      // Tapa no botão de entrar.
      await tester.tap(find.text('Entrar').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Deve ter chamado signIn com o e-mail.
      expect(auth.calls.where((c) => c.startsWith('signIn:test@veredas.org')),
          isNotEmpty);
    });

    testWidgets('mostra erro de credenciais inválidas', (tester) async {
      final auth = FakeAuthService();
      auth.signInError = makeAuthException(AppErrorCode.invalidCredentials);

      await tester.pumpWidget(
        buildTestWidgetWithRouter(
          initialLocation: '/login',
          child: const LoginScreen(),
          auth: auth,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(CupertinoTextFormFieldRow).at(0),
          'wrong@veredas.org');
      await tester.enterText(find.byType(CupertinoTextFormFieldRow).at(1),
          'wrongpass');
      await tester.pump();

      await tester.tap(find.text('Entrar').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Deve mostrar a mensagem de erro mapeada.
      expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
    });

    testWidgets('mostra botão de reenviar confirmação quando e-mail não confirmado',
        (tester) async {
      final auth = FakeAuthService();
      auth.signInError = makeAuthException(AppErrorCode.emailNotConfirmed);

      await tester.pumpWidget(
        buildTestWidgetWithRouter(
          initialLocation: '/login',
          child: const LoginScreen(),
          auth: auth,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(CupertinoTextFormFieldRow).at(0),
          'unconfirmed@veredas.org');
      await tester.enterText(find.byType(CupertinoTextFormFieldRow).at(1),
          'password123');
      await tester.pump();

      await tester.tap(find.text('Entrar').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Deve mostrar a mensagem de e-mail não confirmado.
      expect(find.text('Seu e-mail ainda não foi confirmado.'),
          findsOneWidget);
      // E o botão de reenviar.
      expect(find.text('Reenviar confirmação'), findsOneWidget);
    });

    testWidgets('navega para esqueci-senha ao tocar no link',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(
            path: '/login',
            builder: (_, _) => const LoginScreen(),
          ),
          GoRoute(
            path: '/esqueci-senha',
            builder: (_, _) => const _DummyScreen(label: 'esqueci-senha'),
          ),
        ],
      );

      final auth = FakeAuthService();
      final db = createTestDatabase();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) {
              ref.onDispose(db.close);
              return db;
            }),
            authServiceProvider.overrideWithValue(auth),
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
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Toca em "Esqueci minha senha".
      await tester.tap(find.text('Esqueci minha senha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Deve ter navegado para a tela dummy.
      expect(find.text('esqueci-senha'), findsOneWidget);
    });
  });
}

class _DummyScreen extends StatelessWidget {
  const _DummyScreen({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(child: Center(child: Text(label)));
  }
}
