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
///
/// [onRefresh] substitui o sync, para a tela que não lê do cache — a de
/// membros removidos consulta o servidor na hora.
class SyncRefreshControl extends ConsumerWidget {
  const SyncRefreshControl({this.onRefresh, super.key});

  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoSliverRefreshControl(
      // O Future só completa quando o sync termina, e é isso que mantém o
      // indicador girando pelo tempo certo em vez de sumir na hora.
      onRefresh:
          onRefresh ?? () => ref.read(syncStatusProvider.notifier).pullAll(),
    );
  }
}

/// `ListView` arrastável para atualizar — o que as telas de Administração
/// usavam, trocado por um `CustomScrollView`, que é o que o
/// `CupertinoSliverRefreshControl` exige.
///
/// Sem [padding], reserva embaixo a área segura, como o `ListView` faz
/// sozinho e o `CustomScrollView` não: as telas de admin usam
/// `SafeArea(bottom: false)` e contam com isso para o último item não ficar
/// sob o indicador de início do iPhone.
class RefreshableListView extends StatelessWidget {
  const RefreshableListView({
    required this.children,
    this.padding,
    this.onRefresh,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SyncRefreshControl(onRefresh: onRefresh),
        SliverPadding(
          padding: padding ??
              EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          sliver: SliverList.list(children: children),
        ),
      ],
    );
  }
}

/// Torna um conteúdo não rolável arrastável para atualizar.
///
/// [child] recebe a altura da viewport (via `SliverFillRemaining`), preservando
/// widgets que se centralizam sozinhos — é o caso do `EmptyState` e do
/// `LoadingState`.
class RefreshableBox extends StatelessWidget {
  const RefreshableBox({required this.child, this.onRefresh, super.key});

  final Widget child;

  /// Ver [SyncRefreshControl.onRefresh].
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      // Sem `alwaysScrollable` não há overscroll num conteúdo que cabe na
      // tela, e sem overscroll o gesto simplesmente não acontece.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SyncRefreshControl(onRefresh: onRefresh),
        SliverFillRemaining(
          hasScrollBody: false,
          child: child,
        ),
      ],
    );
  }
}
