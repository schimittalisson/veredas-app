import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/error/app_exception.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Estado de sincronização exibido na UI (OfflineBanner, indicadores).
enum SyncStatus {
  /// Nada pendente, tudo em dia.
  idle,

  /// Sincronizando (pull ou drenagem da outbox em andamento).
  syncing,

  /// Sem conexão. Escritas ficam na outbox; leitura usa o cache local.
  offline,

  /// Última sincronização falhou. O usuário pode tentar de novo.
  error,
}

/// Estado de sincronização do app, derivado de conectividade + outbox + sync.
///
/// A UI observa este provider para mostrar o `OfflineBanner` e indicadores
/// de "sincronizando…". Não é um enum puro porque a transição entre estados
/// tem lógica: `offline` tem prioridade sobre `syncing` (não adianta dizer
/// "sincronizando" se não há rede), e `error` só aparece se não estiver
/// offline (erro de rede é offline, não error).
class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() {
    // Observa conectividade e outbox pendente para derivar o estado.
    final isOnline = ref.watch(isOnlineProvider);
    final hasPending = ref.watch(hasPendingOutboxProvider).value ?? false;

    if (!isOnline) {
      // Offline: se há pendentes, mostra offline (não error — a escrita
      // está na fila e será enviada quando voltar a conexão).
      return SyncStatus.offline;
    }

    if (hasPending || _isSyncing) {
      return SyncStatus.syncing;
    }

    return _lastError != null ? SyncStatus.error : SyncStatus.idle;
  }

  bool _isSyncing = false;
  AppErrorCode? _lastError;

  /// Dispara um pull completo. Chamado no login, no resume do app, ao voltar
  /// a conexão, e por pull-to-refresh.
  Future<void> pullAll() async {
    if (_isSyncing) return;
    _isSyncing = true;
    state = SyncStatus.syncing;

    try {
      // **Drena ANTES de puxar.** A ordem importa:
      //
      // 1. Um pull `fullReplace` (é o caso de `prayer_feed`) faz `clear()` na
      //    tabela local. Se o pull vier primeiro, ele apaga a linha otimista
      //    que ainda não subiu — a oração recém-criada desaparecia da tela e
      //    só reaparecia no sync seguinte, quando já estava no servidor.
      // 2. Enviar primeiro e puxar depois deixa o cache com o estado
      //    autoritativo do servidor no mesmo ciclo (contadores, nome do autor
      //    e o que mais a view calcula), corrigindo o otimismo de imediato.
      await ref.read(outboxWorkerProvider).drain();
      await ref.read(syncServiceProvider).pullAll();
      _lastError = null;
    } on AppException catch (e) {
      _lastError = e.code;
    } finally {
      _isSyncing = false;
      // Recalcula o estado.
      final isOnline = ref.read(isOnlineProvider);
      final hasPending =
          ref.read(hasPendingOutboxProvider).value ?? false;
      if (!isOnline) {
        state = SyncStatus.offline;
      } else if (hasPending) {
        state = SyncStatus.syncing;
      } else {
        state = _lastError != null ? SyncStatus.error : SyncStatus.idle;
      }
    }
  }

  /// Limpa o erro (após o usuário ver e dispensar).
  void clearError() {
    _lastError = null;
    if (state == SyncStatus.error) {
      state = ref.read(isOnlineProvider)
          ? SyncStatus.idle
          : SyncStatus.offline;
    }
  }
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);
