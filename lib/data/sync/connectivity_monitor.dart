import 'package:connectivity_plus/connectivity_plus.dart';

/// Monitor de conectividade abstrato.
///
/// Segue o padrão do `PLANO.md §2.4` — o mesmo de [RemoteSource] e
/// `AuthService`: o plugin fica atrás de uma interface, para o comportamento ser
/// testável sem `MethodChannel` nem rede.
///
/// **Por que valeu extrair.** A fronteira com o `connectivity_plus` esconde uma
/// distinção fácil de perder: `onConnectivityChanged` entrega apenas *mudanças*
/// (a documentação é explícita e o stream aplica `distinct`), nunca o estado
/// atual. Quem depende só dele fica sem saber se há rede até ela oscilar. E
/// como `isOnlineProvider` lia "sem valor" como offline, o
/// `OutboxWorker.drain()` desistia antes de tentar e **nenhuma escrita saía do
/// aparelho**. Os dois métodos abaixo existem separados justamente para que
/// essa diferença fique explícita em vez de implícita no plugin.
abstract class ConnectivityMonitor {
  /// Estado atual, consultado uma vez. É o que semeia o stream.
  Future<List<ConnectivityResult>> current();

  /// Mudanças de estado. **Não** emite o estado atual ao inscrever.
  Stream<List<ConnectivityResult>> changes();
}

/// Implementação de [ConnectivityMonitor] sobre o `connectivity_plus`.
class PluginConnectivityMonitor implements ConnectivityMonitor {
  PluginConnectivityMonitor([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<List<ConnectivityResult>> current() =>
      _connectivity.checkConnectivity();

  @override
  Stream<List<ConnectivityResult>> changes() =>
      _connectivity.onConnectivityChanged;
}
