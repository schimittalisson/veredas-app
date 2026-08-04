import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/ui/screens/agenda/agenda_screen.dart';
import 'package:veredas/ui/screens/home/home_screen.dart';
import 'package:veredas/ui/screens/prayer/prayer_wall_screen.dart';
import 'package:veredas/ui/screens/scales/scales_screen.dart';
import 'package:veredas/ui/widgets/root_scaffold.dart';

/// Rotas do app em constantes, para não espalhar strings literais pelas telas.
class Routes {
  const Routes._();

  static const String inicio = '/inicio';
  static const String agenda = '/agenda';
  static const String escalas = '/escalas';
  static const String oracao = '/oracao';

  // Rotas de autenticação (Fase 3).
  static const String login = '/login';
  static const String cadastro = '/cadastro';
  static const String esqueciSenha = '/esqueci-senha';
  static const String aguardando = '/aguardando';

  /// Rotas onde um usuário sem sessão pode estar. O `redirect` da Fase 3 usa
  /// esta lista para não entrar em loop de redirecionamento.
  static const Set<String> unauthenticated = {
    login,
    cadastro,
    esqueciSenha,
  };
}

/// Chave do navigator raiz.
///
/// Necessária para empilhar rotas *acima* da `NavigationBar` (ex.: o editor de
/// evento, que ocupa a tela inteira). Sem ela, a rota abriria dentro do branch
/// e a barra de tabs continuaria visível.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// O router é um **provider**, não uma variável global.
///
/// Na Fase 3 o `redirect` precisa ler o estado de autenticação do Riverpod para
/// decidir entre `/login`, `/aguardando` e `/inicio`. Um `GoRouter` global não
/// tem acesso ao container.
///
/// Cuidado ao evoluir isto: **não** faça `ref.watch` do estado de auth aqui.
/// Recriar o `GoRouter` a cada mudança de sessão descarta todo o histórico de
/// navegação. O padrão correto é um router estável + `refreshListenable` ligado
/// ao stream de auth, com a decisão dentro do `redirect`.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.inicio,
    debugLogDiagnostics: false,
    routes: [
      StatefulShellRoute.indexedStack(
        // indexedStack mantém as 4 tabs vivas simultaneamente. Isso interage
        // com o Riverpod 3: providers fora de tela são pausados, mas as tabs
        // aqui nunca saem da árvore, então seus StreamProviders continuam
        // recebendo eventos do drift.
        builder: (context, state, navigationShell) =>
            RootScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.inicio,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.agenda,
                builder: (context, state) => const AgendaScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.escalas,
                builder: (context, state) => const ScalesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.oracao,
                builder: (context, state) => const PrayerWallScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
