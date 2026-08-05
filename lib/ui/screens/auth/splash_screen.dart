import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/providers/auth_providers.dart';

/// Tela de splash. Mostra a logo brevemente enquanto resolve a sessão.
///
/// Nunca fica visível mais de ~1s: o `redirect` do router decide o destino
/// (login, aguardando ou inicio) assim que o `authStateProvider` resolve.
/// Se o auth ainda está carregando, a splash fica visível — é o estado
/// "carregando" do app inteiro.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.jpg',
              width: 120,
              height: 120,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            // Só mostra o spinner se o auth ainda não resolveu. Quando
            // resolve, o redirect já mandou para a próxima tela.
            if (authState.isLoading)
              const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
