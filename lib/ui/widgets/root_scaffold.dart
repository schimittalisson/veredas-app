import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/ui/widgets/offline_banner.dart';

/// Casca das 4 tabs, com a `CupertinoTabBar`.
///
/// O `StatefulNavigationShell` do go_router mantém um `Navigator` por branch,
/// então o estado de cada tab (posição de scroll, semana selecionada nas
/// escalas, texto na busca do mural) sobrevive à troca de tab.
///
/// **Não usa `CupertinoTabScaffold`** de propósito: ele gerencia o índice da
/// tab internamente, o que competiria com o go_router pelo controle da
/// navegação. A `CupertinoTabBar` é montada solta, com o índice vindo do
/// shell — assim as rotas continuam sendo a única fonte da verdade.
class RootScaffold extends ConsumerWidget {
  const RootScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      // Tocar na tab JÁ ativa volta ao topo daquele branch. É o comportamento
      // que o usuário espera (igual ao Instagram/Twitter) e o único jeito de
      // sair de uma tela empilhada dentro da tab sem usar o botão voltar.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      child: Column(
        children: [
          // O banner fica acima do conteúdo da tab, abaixo da status bar.
          const SafeArea(bottom: false, child: OfflineBanner()),
          Expanded(child: navigationShell),
          CupertinoTabBar(
            currentIndex: navigationShell.currentIndex,
            onTap: _onDestinationSelected,
            backgroundColor: colors.elevatedSurface,
            activeColor: colors.tint,
            inactiveColor: colors.secondaryLabel,
            border: Border(
              top: BorderSide(color: colors.separator, width: 0.5),
            ),
            items: [
              BottomNavigationBarItem(
                icon: const Icon(CupertinoIcons.house),
                activeIcon: const Icon(CupertinoIcons.house_fill),
                label: l.tab_inicio,
              ),
              BottomNavigationBarItem(
                icon: const Icon(CupertinoIcons.calendar),
                activeIcon: const Icon(CupertinoIcons.calendar_today),
                label: l.tab_agenda,
              ),
              BottomNavigationBarItem(
                icon: const Icon(CupertinoIcons.list_bullet),
                activeIcon: const Icon(CupertinoIcons.list_bullet_indent),
                label: l.tab_escalas,
              ),
              BottomNavigationBarItem(
                icon: const Icon(CupertinoIcons.heart),
                activeIcon: const Icon(CupertinoIcons.heart_fill),
                label: l.tab_oracao,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
