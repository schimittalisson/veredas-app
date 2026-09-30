import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/widgets/auth_link_error_listener.dart';

import '../helpers/test_helpers.dart';

// O bug: o link de recuperação aberto noutro aparelho (ou vencido, ou de um
// e-mail anterior) abria o app e nada acontecia. O erro existia, mas ia para
// um stream que ninguém lia.

void main() {
  late FakeAuthService auth;

  setUp(() => auth = FakeAuthService());
  tearDown(() => auth.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        // Como no app.dart: o listener fica no `builder`, acima do Navigator,
        // e abre o alerta pelo navigator raiz.
        child: CupertinoApp(
          navigatorKey: rootNavigatorKey,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => AuthLinkErrorListener(child: child!),
          home: const CupertinoPageScaffold(child: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('link que falhou mostra o aviso, toda vez', (tester) async {
    await pumpApp(tester);
    expect(find.text('Não foi possível usar o link'), findsNothing);

    auth.simulateAuthLinkError();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Não foi possível usar o link'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pump();
    // A saída do alerta do iOS anima; espera ela terminar.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Não foi possível usar o link'), findsNothing);

    // O segundo link ruim avisa de novo. Um StreamProvider engoliria este:
    // o Riverpod 3 filtra valores iguais com `==`.
    auth.simulateAuthLinkError();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Não foi possível usar o link'), findsOneWidget);
  });
}
