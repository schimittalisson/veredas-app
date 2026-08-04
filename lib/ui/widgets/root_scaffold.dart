import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/l10n/app_localizations.dart';

/// Casca das 4 tabs, com a `NavigationBar` do Material 3.
///
/// O `StatefulNavigationShell` do go_router mantém um `Navigator` por branch,
/// então o estado de cada tab (posição de scroll, semana selecionada nas
/// escalas, texto na busca do mural) sobrevive à troca de tab.
class RootScaffold extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l.tab_inicio,
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month),
            label: l.tab_agenda,
          ),
          NavigationDestination(
            icon: const Icon(Icons.assignment_outlined),
            selectedIcon: const Icon(Icons.assignment),
            label: l.tab_escalas,
          ),
          NavigationDestination(
            icon: const Icon(Icons.favorite_outline),
            selectedIcon: const Icon(Icons.favorite),
            label: l.tab_oracao,
          ),
        ],
      ),
    );
  }
}
