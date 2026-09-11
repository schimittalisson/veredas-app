import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/data/remote/auth_service.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/screens/auth/splash_screen.dart';

import '../helpers/widget_test_helpers.dart';

/// A splash existe para imitar o splash nativo. Se a logo mudar de tamanho ou
/// sair do centro, o usuário vê um segundo splash piscando na abertura — que
/// é exatamente o bug que estes testes travam.
void main() {
  /// Mantém o auth num estado resolvido (ou carregando, com [loading]).
  List<dynamic> overrides({
    bool authLoading = false,
    bool bootstrapLoading = false,
  }) =>
      [
        authStateProvider.overrideWith(
          (ref) => authLoading
              // Stream que nunca emite: o AsyncValue fica em isLoading.
              ? const Stream<AuthState>.empty().asBroadcastStream()
              : Stream.value(AuthState.unauthenticated),
        ),
        profileBootstrapProvider.overrideWith(
          (ref) => bootstrapLoading
              // Future que nunca completa: o provider fica em isLoading.
              ? Completer<void>().future
              : Future<void>.value(),
        ),
      ];

  /// Retângulo da logo na tela.
  Rect logoRect(WidgetTester tester) =>
      tester.getRect(find.byType(Image).first);

  Future<void> pumpSplash(
    WidgetTester tester, {
    bool authLoading = false,
    bool bootstrapLoading = false,
  }) async {
    await tester.pumpWidget(buildTestWidget(
      child: const SplashScreen(),
      additionalOverrides: overrides(
        authLoading: authLoading,
        bootstrapLoading: bootstrapLoading,
      ),
    ));
    // Dois pumps: o primeiro monta a árvore, o segundo entrega o valor do
    // Stream/Future (que chegam num microtask). Sem o segundo, um provider já
    // resolvido ainda aparece como isLoading.
    //
    // Sem pumpAndSettle: o CupertinoActivityIndicator anima para sempre e a
    // suíte travaria esperando a árvore assentar.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('SplashScreen — continuidade com o splash nativo', () {
    testWidgets('a logo mede 168, o tamanho que casa com o LaunchImage do iOS',
        (tester) async {
      await pumpSplash(tester);

      final rect = logoRect(tester);
      expect(rect.width, 168);
      expect(rect.height, 168);
    });

    testWidgets('a logo fica no centro exato da tela', (tester) async {
      await pumpSplash(tester);

      final screen = tester.getRect(find.byType(CupertinoPageScaffold));
      expect(logoRect(tester).center, screen.center);
    });

    // Percorre a transição real, na mesma árvore: o bootstrap termina e o
    // spinner some. Remontar a árvore com outros overrides não serviria —
    // o Riverpod trataria como refresh e o estado não seria o mesmo.
    testWidgets('o spinner não desloca a logo ao sumir', (tester) async {
      final bootstrap = Completer<void>();

      await tester.pumpWidget(buildTestWidget(
        child: const SplashScreen(),
        additionalOverrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(AuthState.unauthenticated),
          ),
          profileBootstrapProvider.overrideWith((ref) => bootstrap.future),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      final comSpinner = logoRect(tester);

      bootstrap.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      // Numa Column a logo desceria ao o spinner sumir.
      expect(logoRect(tester), comSpinner);
    });
  });

  group('SplashScreen — indicador de carregamento', () {
    testWidgets('mostra o spinner enquanto o auth resolve', (tester) async {
      await pumpSplash(tester, authLoading: true);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    });

    // O bug: depois do login numa instalação nova o auth já resolveu, mas o
    // perfil ainda está sendo puxado (~1-2s de rede). A condição antiga só
    // olhava o auth, então a logo ficava parada sem indicador nenhum e o app
    // parecia travado.
    testWidgets('mostra o spinner enquanto o perfil é puxado, com o auth já '
        'resolvido', (tester) async {
      await pumpSplash(tester, bootstrapLoading: true);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    });

    testWidgets('esconde o spinner quando auth e perfil resolveram',
        (tester) async {
      await pumpSplash(tester);

      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });
  });
}
