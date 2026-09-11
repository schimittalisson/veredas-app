import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/providers/sync_providers.dart';

/// Pull-to-refresh das abas principais.
///
/// **Por que existe.** O app não assina realtime: o cache só é atualizado por
/// `pullAll()`, que dispara na abertura, no retorno do segundo plano e na volta
/// da conexão. Sem um gesto explícito, uma oração criada em outro aparelho só
/// aparecia depois de mandar o app para o segundo plano e voltar.
///
/// Usa `CupertinoSliverRefreshControl` e não o `RefreshIndicator` do Material:
/// o app é inteiramente Cupertino, e o indicador do Material apareceria como um
/// corpo estranho na tela. O preço é que o scroll precisa ser um
/// `CustomScrollView` — daí os dois formatos abaixo.
///
/// - [SyncRefreshControl] para quem já rola uma lista: entra como primeiro
///   sliver do `CustomScrollView`.
/// - [RefreshableBox] para conteúdo **não rolável** (estado vazio, erro,
///   carregando). É justamente aí que o gesto mais importa: a tela está vazia e
///   o usuário quer justamente buscar novidade. Sem isto, a lista vazia não
///   rolaria e o gesto não existiria.
///
/// O `pullAll()` já se protege de chamadas concorrentes, então arrastar duas
/// vezes seguidas não dispara dois syncs.

/// Sliver de pull-to-refresh. Primeiro item de um `CustomScrollView`.
class SyncRefreshControl extends ConsumerWidget {
  const SyncRefreshControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoSliverRefreshControl(
      // O Future só completa quando o sync termina, e é isso que mantém o
      // indicador girando pelo tempo certo em vez de sumir na hora.
      onRefresh: () => ref.read(syncStatusProvider.notifier).pullAll(),
    );
  }
}

/// Torna um conteúdo não rolável arrastável para atualizar.
///
/// [child] recebe a altura da viewport (via `SliverFillRemaining`), preservando
/// widgets que se centralizam sozinhos — é o caso do `EmptyState` e do
/// `LoadingState`.
class RefreshableBox extends StatelessWidget {
  const RefreshableBox({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      // Sem `alwaysScrollable` não há overscroll num conteúdo que cabe na
      // tela, e sem overscroll o gesto simplesmente não acontece.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SyncRefreshControl(),
        SliverFillRemaining(
          hasScrollBody: false,
          child: child,
        ),
      ],
    );
  }
}
