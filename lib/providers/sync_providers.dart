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

    return _derive(isOnline: isOnline, hasPending: hasPending);
  }

  /// Regra única de derivação do estado, usada pelo `build()` e pelo fim de
  /// `pullAll()` — duas cópias divergiriam.
  ///
  /// **`error` vem antes de `hasPending`.** Enquanto a fila era visível, o
  /// contrário fazia sentido: "aguardando envio" já dizia ao usuário que algo
  /// não subiu. Com a faixa de pendentes removida (ver `OfflineBanner`), pôr
  /// `syncing` na frente engoliria o aviso de falha justamente no caso em que
  /// ele importa — a entrada que falhou continua na fila, então `hasPending`
  /// fica `true` e o banner de erro nunca apareceria.
  SyncStatus _derive({required bool isOnline, required bool hasPending}) {
    // Offline tem prioridade: não adianta dizer "erro" para quem está sem
    // rede, a escrita está na fila e sai quando a conexão voltar.
    if (!isOnline) return SyncStatus.offline;
    if (_lastError != null) return SyncStatus.error;
    if (hasPending || _isSyncing) return SyncStatus.syncing;
    return SyncStatus.idle;
  }

  bool _isSyncing = false;

  /// Marca que um gatilho chegou enquanto um ciclo já estava rodando.
  bool _syncRequested = false;

  AppErrorCode? _lastError;

  /// Dispara um pull completo. Chamado no login, no resume do app, ao voltar
  /// a conexão, e por pull-to-refresh.
  Future<void> pullAll() async {
    if (_isSyncing) {
      // **Não descarte o pedido.** Um gatilho pode chegar no meio de um ciclo
      // — tipicamente uma escrita que entra na outbox depois de o `drain()`
      // já ter lido a fila. Voltando aqui sem anotar nada, essa entrada ficava
      // parada até o próximo resume do app: a fila nunca volta de vazia para
      // cheia, então o gatilho de pendentes também não dispara de novo.
      _syncRequested = true;
      return;
    }

    _isSyncing = true;
    state = SyncStatus.syncing;

    try {
      do {
        // Zera antes do ciclo: o que chegar durante os `await` abaixo pede
        // uma repetição, o que chegou antes já está sendo atendido.
        _syncRequested = false;

        // **Drena ANTES de puxar.** A ordem importa:
        //
        // 1. Um pull `fullReplace` (é o caso de `prayer_feed`) faz `clear()`
        //    na tabela local. Se o pull vier primeiro, ele apaga a linha
        //    otimista que ainda não subiu — a oração recém-criada desaparecia
        //    da tela e só reaparecia no sync seguinte, quando já estava no
        //    servidor.
        // 2. Enviar primeiro e puxar depois deixa o cache com o estado
        //    autoritativo do servidor no mesmo ciclo (contadores, nome do
        //    autor e o que mais a view calcula), corrigindo o otimismo de
        //    imediato.
        await ref.read(outboxWorkerProvider).drain();
        await ref.read(syncServiceProvider).pullAll();
      } while (_syncRequested);
      _lastError = null;
    } on AppException catch (e) {
      _lastError = e.code;
    } finally {
      _isSyncing = false;
      _syncRequested = false;
      state = _derive(
        isOnline: ref.read(isOnlineProvider),
        hasPending: ref.read(hasPendingOutboxProvider).value ?? false,
      );
    }
  }

  /// Limpa o erro (após o usuário ver e dispensar).
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    state = _derive(
      isOnline: ref.read(isOnlineProvider),
      hasPending: ref.read(hasPendingOutboxProvider).value ?? false,
    );
  }
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);
