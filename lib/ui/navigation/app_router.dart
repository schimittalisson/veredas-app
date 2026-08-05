import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/data/models/profile.dart';
import 'package:veredas/data/remote/auth_service.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/ui/screens/admin/admin_screen.dart';
import 'package:veredas/ui/screens/admin/convites_screen.dart';
import 'package:veredas/ui/screens/admin/membros_screen.dart';
import 'package:veredas/ui/screens/admin/responsaveis_screen.dart';
import 'package:veredas/ui/screens/agenda/agenda_screen.dart';
import 'package:veredas/ui/screens/agenda/event_editor_screen.dart';
import 'package:veredas/ui/screens/agenda/weekly_slot_editor_screen.dart';
import 'package:veredas/ui/screens/auth/aguardando_screen.dart';
import 'package:veredas/ui/screens/auth/cadastro_screen.dart';
import 'package:veredas/ui/screens/auth/esqueci_senha_screen.dart';
import 'package:veredas/ui/screens/auth/login_screen.dart';
import 'package:veredas/ui/screens/auth/splash_screen.dart';
import 'package:veredas/ui/screens/home/announcement_editor_screen.dart';
import 'package:veredas/ui/screens/home/home_screen.dart';
import 'package:veredas/ui/screens/prayer/prayer_editor_screen.dart';
import 'package:veredas/ui/screens/prayer/prayer_wall_screen.dart';
import 'package:veredas/ui/screens/scales/scale_assignment_editor_screen.dart';
import 'package:veredas/ui/screens/scales/scales_screen.dart';
import 'package:veredas/ui/widgets/root_scaffold.dart';

/// Rotas do app em constantes, para não espalhar strings literais pelas telas.
class Routes {
  const Routes._();

  static const String splash = '/';
  static const String inicio = '/inicio';
  static const String agenda = '/agenda';
  static const String escalas = '/escalas';
  static const String oracao = '/oracao';

  // Rotas de autenticação.
  static const String login = '/login';
  static const String cadastro = '/cadastro';
  static const String esqueciSenha = '/esqueci-senha';
  static const String aguardando = '/aguardando';

  // Rotas de administração.
  static const String admin = '/admin';
  static const String adminMembros = '/admin/membros';
  static const String adminConvites = '/admin/convites';
  static const String adminResponsaveis = '/admin/responsaveis';
  static const String adminBase = '/admin/base';

  // Rotas de editores (acima da NavigationBar, tela inteira).
  static const String avisoNovo = '/aviso/novo';
  static const String avisoEditar = '/aviso/editar';
  static const String oracaoNovo = '/oracao/novo';
  static const String oracaoEditar = '/oracao/editar';
  static const String eventoNovo = '/evento/novo';
  static const String eventoEditar = '/evento/editar';
  static const String slotNovo = '/cronograma/novo';
  static const String slotEditar = '/cronograma/editar';
  static const String escalaAtribuicaoNovo = '/escala/atribuicao/novo';
  static const String escalaAtribuicaoEditar = '/escala/atribuicao/editar';

  /// Rotas onde um usuário sem sessão pode estar. O `redirect` usa esta lista
  /// para não entrar em loop de redirecionamento.
  ///
  /// **A splash não entra aqui.** Ela é o estado "auth carregando", tratado
  /// antes de tudo no `_redirect`. Se estivesse nesta lista, um usuário sem
  /// sessão ficaria preso nela: a regra 1 devolveria null e nada o tiraria de lá.
  static const Set<String> unauthenticated = {
    login,
    cadastro,
    esqueciSenha,
  };

  /// Rotas onde um usuário **não aprovado** pode estar. Sem isto, o redirect
  /// mandaria o usuário para `/aguardando` mesmo quando ele já está lá.
  static const Set<String> unapproved = {
    aguardando,
    login,
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
/// O `redirect` precisa ler o estado de autenticação do Riverpod para decidir
/// entre `/login`, `/aguardando` e `/inicio`.
///
/// **Cuidado ao evoluir isto:** não faça `ref.watch` do estado de auth aqui.
/// Recriar o `GoRouter` a cada mudança de sessão descarta todo o histórico de
/// navegação. O padrão correto é um router estável + `refreshListenable`
/// ligado a um `ValueNotifier` que muda quando o auth muda, com a decisão
/// dentro do `redirect` lendo o container do Riverpod.
final routerProvider = Provider<GoRouter>((ref) {
  // ValueNotifier que muda quando o estado de auth muda. O GoRouter observa
  // isto via refreshListenable e reavalia o redirect.
  final refreshNotifier = _RouterRefreshNotifier();

  // Escuta o authStateProvider e o currentProfileProvider. Quando qualquer
  // um muda, dispara o refreshNotifier — o GoRouter reavalia o redirect.
  ref.listen<AsyncValue<AuthState>>(
    authStateProvider,
    (_,_) => refreshNotifier.refresh(),
    fireImmediately: true,
  );
  ref.listen<AsyncValue<Profile?>>(
    currentProfileProvider,
    (_,_) => refreshNotifier.refresh(),
    fireImmediately: true,
  );

  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refreshNotifier,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      return _redirect(ref, state.matchedLocation);
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.cadastro,
        builder: (context, state) => const CadastroScreen(),
      ),
      GoRoute(
        path: Routes.esqueciSenha,
        builder: (context, state) => const EsqueciSenhaScreen(),
      ),
      GoRoute(
        path: Routes.aguardando,
        builder: (context, state) => const AguardandoScreen(),
      ),
      // Rotas de administração — guard no redirect verifica isAdmin.
      GoRoute(
        path: Routes.admin,
        builder: (context, state) => const AdminScreen(),
      ),
      GoRoute(
        path: Routes.adminMembros,
        builder: (context, state) => const MembrosScreen(),
      ),
      GoRoute(
        path: Routes.adminConvites,
        builder: (context, state) => const ConvitesScreen(),
      ),
      GoRoute(
        path: Routes.adminResponsaveis,
        builder: (context, state) => const ResponsaveisScreen(),
      ),
      GoRoute(
        path: Routes.adminBase,
        builder: (context, state) => const AdminScreen(), // TODO: BaseDataScreen
      ),
      // Editores — tela inteira, acima da NavigationBar.
      GoRoute(
        path: Routes.avisoNovo,
        builder: (context, state) => const AnnouncementEditorScreen(),
      ),
      GoRoute(
        path: Routes.avisoEditar,
        builder: (context, state) => AnnouncementEditorScreen(
          announcementId: state.uri.queryParameters['id'],
        ),
      ),
      GoRoute(
        path: Routes.oracaoNovo,
        builder: (context, state) => const PrayerEditorScreen(),
      ),
      GoRoute(
        path: Routes.oracaoEditar,
        builder: (context, state) => PrayerEditorScreen(
          postId: state.uri.queryParameters['id'],
        ),
      ),
      GoRoute(
        path: Routes.eventoNovo,
        builder: (context, state) => const EventEditorScreen(),
      ),
      GoRoute(
        path: Routes.eventoEditar,
        builder: (context, state) => EventEditorScreen(
          eventId: state.uri.queryParameters['id'],
        ),
      ),
      GoRoute(
        path: Routes.slotNovo,
        builder: (context, state) => const WeeklySlotEditorScreen(),
      ),
      GoRoute(
        path: Routes.slotEditar,
        builder: (context, state) => WeeklySlotEditorScreen(
          slotId: state.uri.queryParameters['id'],
        ),
      ),
      GoRoute(
        path: Routes.escalaAtribuicaoNovo,
        builder: (context, state) => ScaleAssignmentEditorScreen(
          scaleTypeId: state.uri.queryParameters['scaleTypeId']!,
        ),
      ),
      GoRoute(
        path: Routes.escalaAtribuicaoEditar,
        builder: (context, state) => ScaleAssignmentEditorScreen(
          scaleTypeId: state.uri.queryParameters['scaleTypeId']!,
          assignmentId: state.uri.queryParameters['id'],
        ),
      ),
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

/// Lógica de redirecionamento, extraída para poder testar isoladamente.
///
/// Regras (PLANO.md Fase 3):
/// 1. Sem sessão → `/login` (exceto se já em rota de auth).
/// 2. Com sessão e `is_approved == false` → `/aguardando` (exceto se já em
///    rota permitida para não aprovado).
/// 3. Com sessão aprovada em rota de auth → `/inicio`.
/// 4. Caso contrário, null (segue o fluxo normal).
///
/// O perfil pode ser null mesmo com sessão (ainda não sincronizado). Nesse
/// caso, trata como "não aprovado" — o `/aguardando` tem um botão "verificar
/// novamente" que refaz o fetch.
String? _redirect(Ref ref, String location) {
  final authAsync = ref.read(authStateProvider);

  // 0. Auth ainda não resolveu: a splash é o "carregando" do app inteiro.
  //    Só ficamos nela enquanto isLoading — sem esta guarda, a splash não
  //    tem saída, porque ela está em `unauthenticated` e a regra 1 devolveria
  //    null para sempre.
  if (authAsync.isLoading) {
    return location == Routes.splash ? null : Routes.splash;
  }

  final isAuthenticated = authAsync.value?.isAuthenticated ?? false;

  // 1. Sem sessão.
  if (!isAuthenticated) {
    if (Routes.unauthenticated.contains(location)) return null;
    return Routes.login;
  }

  // 2. Com sessão — verifica aprovação.
  //
  //    O perfil vem de um StreamProvider sobre o cache. Enquanto ele não
  //    emite, `value` é null. Tratar isso como "não aprovado" mandaria um
  //    usuário aprovado para /aguardando por uma fração de segundo, até o
  //    stream emitir. Então: perfil ainda carregando = fica na splash.
  final profileAsync = ref.read(currentProfileProvider);
  if (profileAsync.isLoading) {
    return location == Routes.splash ? null : Routes.splash;
  }

  final profile = profileAsync.value;
  final isApproved = profile?.isApproved ?? false;

  if (!isApproved) {
    if (Routes.unapproved.contains(location)) return null;
    return Routes.aguardando;
  }

  // 3. Aprovado em rota de auth/splash/aguardando → manda para /inicio.
  if (Routes.unauthenticated.contains(location) ||
      location == Routes.splash ||
      location == Routes.aguardando) {
    return Routes.inicio;
  }

  // 4. Rota de admin sem ser admin → manda para /inicio.
  if (location.startsWith('/admin') && !(profile?.isAdmin ?? false)) {
    return Routes.inicio;
  }

  // 5. Tudo certo.
  return null;
}

/// `ValueNotifier` que o GoRouter observa via `refreshListenable`.
///
/// O `ref.listen` no `routerProvider` chama `refresh()` quando o estado de
/// auth ou o perfil muda. O GoRouter então reavalia o `redirect`.
class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
