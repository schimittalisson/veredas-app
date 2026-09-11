import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/ui/widgets/offline_banner.dart';

/// Altura da barra flutuante, sem contar a margem inferior.
const double _kBarHeight = 62;

/// Distância entre a barra e a borda de baixo da área segura.
const double _kBarBottomMargin = 12;

/// Espaço total que a barra ocupa. As telas recebem isto como padding inferior
/// (ver [RootScaffold.build]) para que o último item de uma lista não fique
/// escondido atrás dela.
const double _kBarTotalSpace = _kBarHeight + _kBarBottomMargin * 2;

/// Casca das 5 tabs, com uma barra flutuante arredondada.
///
/// **Cinco é o teto.** O iOS não recomenda passar de cinco itens numa tab bar,
/// e aqui há um limite físico além da diretriz: a pílula divide a largura
/// igualmente entre os itens, então cada rótulo tem ~65 dp num aparelho de
/// 360 dp e menos num estreito. Uma sexta aba, ou um rótulo longo como
/// "Documentos", não cabe — foi por isso que a quinta virou "Arquivos".
///
/// O `StatefulNavigationShell` do go_router mantém um `Navigator` por branch,
/// então o estado de cada tab (posição de scroll, semana selecionada nas
/// escalas, texto na busca do mural) sobrevive à troca de tab.
///
/// **Não usa `CupertinoTabScaffold`** de propósito: ele gerencia o índice da
/// tab internamente, o que competiria com o go_router pelo controle da
/// navegação. A barra é montada solta, com o índice vindo do shell — assim as
/// rotas continuam sendo a única fonte da verdade.
///
/// A barra também não é a `CupertinoTabBar` padrão: o desenho aprovado usa uma
/// **pílula flutuante** sobre o conteúdo, e não uma faixa colada na base. Por
/// isso ela vive num `Stack` e o conteúdo recebe padding equivalente via
/// `MediaQuery`.
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
    final media = MediaQuery.of(context);

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      child: Stack(
        children: [
          // O conteúdo enxerga um padding inferior maior do que o real. As
          // telas usam `SafeArea` e listas com padding, então todas ganham o
          // espaço da barra sem precisar saber que ela existe.
          MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(
                bottom: media.padding.bottom + _kBarTotalSpace,
              ),
            ),
            child: Column(
              children: [
                SafeArea(bottom: false, child: const OfflineBanner()),
                Expanded(child: navigationShell),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: media.padding.bottom + _kBarBottomMargin,
            child: _FloatingTabBar(
              currentIndex: navigationShell.currentIndex,
              onTap: _onDestinationSelected,
              items: [
                (
                  icon: CupertinoIcons.house,
                  activeIcon: CupertinoIcons.house_fill,
                  label: l.tab_inicio,
                ),
                (
                  icon: CupertinoIcons.calendar,
                  activeIcon: CupertinoIcons.calendar_today,
                  label: l.tab_agenda,
                ),
                (
                  icon: CupertinoIcons.list_bullet,
                  activeIcon: CupertinoIcons.list_bullet_indent,
                  label: l.tab_escalas,
                ),
                (
                  icon: CupertinoIcons.heart,
                  activeIcon: CupertinoIcons.heart_fill,
                  label: l.tab_oracao,
                ),
                (
                  icon: CupertinoIcons.folder,
                  activeIcon: CupertinoIcons.folder_fill,
                  label: l.tab_arquivos,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef _TabItem = ({IconData icon, IconData activeIcon, String label});

class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<_TabItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(_kBarHeight / 2),
        border: Border.all(color: colors.separator, width: 0.5),
        // A sombra é o que separa a pílula do conteúdo que passa por baixo.
        // Sem ela, a barra "gruda" visualmente na lista ao rolar.
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: SizedBox(
        height: _kBarHeight,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _TabButton(
                  item: items[i],
                  selected: i == currentIndex,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _TabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? colors.tint : colors.secondaryLabel;

    return GestureDetector(
      // `opaque` para o toque valer em toda a coluna, não só sobre o ícone.
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.activeIcon : item.icon,
              size: 22,
              color: color,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: AppTypography.caption2.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
