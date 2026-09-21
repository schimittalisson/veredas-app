import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/remote/auth_service.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/sync_providers.dart';

/// Dispara a sincronização nos momentos em que ela faz sentido.
///
/// **Por que este widget existe.** A Fase 4 construiu `SyncService` e
/// `OutboxWorker` e os cobriu com testes, mas nada no app chamava `pullAll()`.
/// O resultado era um app que parecia funcionar e não sincronizava: alterações
/// feitas no servidor nunca chegavam ao cache, e escritas feitas no app
/// ficavam na outbox para sempre, porque `drain()` só roda dentro de
/// `pullAll()`.
///
/// Não dá para pendurar isso numa tela: o Riverpod 3 **pausa providers fora de
/// tela**, e um listener presos a um widget que sai da árvore para de receber
/// eventos. Por isso o coordenador fica no nível do `app.dart`, acima do
/// router, como o `AGENTS.md` §4 já prescrevia.
///
/// Os gatilhos:
/// - **Abertura do app**, se já houver sessão (post-frame, para não
///   sincronizar antes da árvore montar).
/// - **Login**, na transição de não autenticado para autenticado.
/// - **Volta da conexão**, na transição de offline para online — é o momento
///   em que a outbox precisa drenar.
/// - **Retorno do segundo plano** (`resumed`), que é quando o usuário volta ao
///   app depois de um tempo e espera ver dados atuais.
/// - **Escrita nova na fila**, na transição de outbox vazia para não vazia.
///
/// `pullAll()` já se protege de chamadas concorrentes com `_isSyncing`, então
/// dois gatilhos disparando juntos não causam sync duplicado.
class SyncCoordinator extends ConsumerStatefulWidget {
  const SyncCoordinator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SyncCoordinator> createState() => _SyncCoordinatorState();
}

class _SyncCoordinatorState extends ConsumerState<SyncCoordinator>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Sincroniza na abertura, se a sessão já estiver restaurada. Vai para o
    // post-frame porque `pullAll` mexe em providers, e fazer isso durante o
    // primeiro build dispara "modified provider during build".
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncIfAuthenticated());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncIfAuthenticated();
  }

  /// O portão é a **sessão**, não a aprovação.
  ///
  /// Gatear por `isApproved` criaria um impasse: o perfil só entra no cache
  /// pelo pull, então um usuário recém-aprovado nunca sincronizaria e nunca
  /// descobriria que foi aprovado. O RLS no servidor já limita o que volta
  /// para quem ainda não tem acesso.
  void _syncIfAuthenticated() {
    if (!mounted) return;
    final auth = ref.read(authStateProvider).value;
    if (auth?.isAuthenticated != true) return;
    unawaited(ref.read(syncStatusProvider.notifier).pullAll());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AuthState>>(authStateProvider, (previous, next) {
      final wasAuthenticated = previous?.value?.isAuthenticated ?? false;
      final isAuthenticated = next.value?.isAuthenticated ?? false;
      if (!wasAuthenticated && isAuthenticated) _syncIfAuthenticated();
    });

    ref.listen<bool>(isOnlineProvider, (previous, next) {
      // Só na transição para online. Sem o `previous != true`, qualquer
      // rebuild do provider de conectividade dispararia um sync.
      if (previous != true && next) _syncIfAuthenticated();
    });

    ref.listen<AsyncValue<bool>>(hasPendingOutboxProvider, (previous, next) {
      // **Uma escrita acabou de entrar na fila.** Faltava este gatilho: com
      // internet funcionando, salvar algo não disparava nada, e a entrada só
      // subia no próximo resume do app ou numa oscilação de rede. Ficava
      // invisível porque a faixa "N alterações aguardando envio" era a única
      // pista — e ela foi removida (ver `OfflineBanner`), então agora o envio
      // precisa mesmo acontecer na hora.
      //
      // Só na transição de vazia para não vazia: a stream reemite a cada
      // mudança na tabela, e sincronizar a cada reemissão de `true` faria um
      // ciclo por entrada.
      if (previous?.value == true || next.value != true) return;
      // Offline não tenta: `drain()` sairia na checagem de conectividade e a
      // volta da conexão já é gatilho próprio.
      if (!ref.read(isOnlineProvider)) return;
      _syncIfAuthenticated();
    });

    return widget.child;
  }
}
