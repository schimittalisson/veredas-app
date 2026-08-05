import 'package:flutter/cupertino.dart';
// `TabController` e `TabBarView` não têm equivalente no Cupertino — são as
// únicas peças do Material que sobreviveram à migração desta tela. Importadas
// nominalmente (`show`) para deixar explícito que nada mais do Material entra
// aqui: a aparência é 100% Cupertino, só a mecânica de troca de página é
// reaproveitada.
import 'package:flutter/material.dart' show TabBarView, TabController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/models/profile.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/scales_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/screens/scales/scale_tab_view.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';

/// Tela Escalas — terceira tab.
///
/// Barra de abas **gerada dinamicamente** de `scale_types` (ordenada por
/// `ordering`, `is_active = true`), rolável na horizontal. Nunca hardcode as
/// abas — adicionar uma escala nova deve ser um `INSERT` no banco, não um
/// release.
class ScalesScreen extends ConsumerWidget {
  const ScalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scaleTypes = ref.watch(activeScaleTypesProvider);

    // A barra de abas precisa estar na mesma subárvore que o TabController, e
    // o controller só pode ser criado depois que sabemos quantas abas existem.
    // Por isso os estados sem abas têm um scaffold próprio (navigation bar sem
    // barra de abas) e o caso com dados delega tudo — navigation bar incluída —
    // para _ScalesBody, que é quem detém o controller.
    return scaleTypes.when(
      loading: () => _ScalesScaffold(title: l.tab_escalas, body: const LoadingState()),
      error: (_,_) => _ScalesScaffold(
        title: l.tab_escalas,
        body: EmptyState(
          title: l.scales_no_types,
          icon: CupertinoIcons.doc_text,
        ),
      ),
      data: (data) {
        if (data.isEmpty) {
          return _ScalesScaffold(
            title: l.tab_escalas,
            body: EmptyState(
              title: l.scales_no_types,
              icon: CupertinoIcons.doc_text,
            ),
          );
        }
        return _ScalesBody(scaleTypes: data);
      },
    );
  }
}

/// Scaffold dos estados sem abas (carregando, erro, nenhuma escala).
class _ScalesScaffold extends StatelessWidget {
  const _ScalesScaffold({required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        backgroundColor: colors.elevatedSurface,
      ),
      child: SafeArea(child: body),
    );
  }
}

class _ScalesBody extends ConsumerStatefulWidget {
  const _ScalesBody({required this.scaleTypes});

  final List<ScaleTypeRow> scaleTypes;

  @override
  ConsumerState<_ScalesBody> createState() => _ScalesBodyState();
}

class _ScalesBodyState extends ConsumerState<_ScalesBody>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = _createController();
  }

  @override
  void didUpdateWidget(_ScalesBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // As escalas vêm do sync: uma nova pode aparecer (ou ser desativada) a
    // qualquer momento. O TabController tem length fixo, então precisa ser
    // recriado — senão o length diverge do número de abas e a troca quebra.
    if (widget.scaleTypes.length != oldWidget.scaleTypes.length) {
      final previousIndex = _tabController.index;
      _tabController.dispose();
      _tabController = _createController(
        // Preserva a aba atual quando ela ainda existe.
        initialIndex: previousIndex.clamp(0, widget.scaleTypes.length - 1),
      );
    }
  }

  TabController _createController({int initialIndex = 0}) {
    return TabController(
      length: widget.scaleTypes.length,
      initialIndex: initialIndex,
      vsync: this,
    )
      // A ação do canto da navigation bar depende da aba ativa (cada escala
      // tem seu próprio scaleTypeId e sua própria permissão) e a barra de abas
      // precisa repintar o item selecionado. Sem este listener, trocar de aba
      // não rebuilda: o botão continua apontando para a escala anterior e o
      // destaque fica na aba errada.
      ..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final profile = ref.watch(currentProfileProvider).value;
    final managedIds = ref.watch(managedScaleTypeIdsProvider);

    final currentType = widget.scaleTypes[_tabController.index];
    final canEdit = _canEditScale(profile, currentType, managedIds);

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.tab_escalas),
        backgroundColor: colors.elevatedSurface,
        // O iOS não tem FAB: a ação de criar mora no canto da navigation bar.
        // Continua condicionada a canEdit e continua carregando o scaleTypeId
        // da aba ativa.
        trailing: canEdit
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  context.push(
                    '${Routes.escalaAtribuicaoNovo}?scaleTypeId=${currentType.id}',
                  );
                },
                child: const Icon(CupertinoIcons.add),
              )
            : null,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ScaleTabBar(
              scaleTypes: widget.scaleTypes,
              controller: _tabController,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: widget.scaleTypes
                    .map((type) => ScaleTabView(
                          scaleType: type,
                          canEdit: _canEditScale(profile, type, managedIds),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Espelha `Profile.canEditScale` mas lida com profile null.
  bool _canEditScale(
    Profile? profile,
    ScaleTypeRow type,
    Set<String> managedIds,
  ) {
    if (profile == null) return false;
    return profile.isAdmin || managedIds.contains(type.id);
  }
}

/// Barra de abas rolável, no lugar da `TabBar` do Material.
///
/// O equivalente idiomático no iOS seria o `CupertinoSlidingSegmentedControl`,
/// mas ele **não rola**: distribui os segmentos na largura disponível. Como as
/// abas vêm do banco (`scale_types`) e a quantidade é variável, um dia com seis
/// ou sete escalas os rótulos ficariam ilegíveis — e não há como chegar na
/// sétima. Por isso a barra é montada à mão: scroll horizontal de
/// `CupertinoButton`, ativa em `tint` com peso maior e sublinhado fino,
/// inativas em `secondaryLabel`.
///
/// Fica no corpo do scaffold, logo abaixo da navigation bar, porque
/// `CupertinoNavigationBar` não tem o slot `bottom` que a `AppBar` tinha.
class _ScaleTabBar extends StatelessWidget {
  const _ScaleTabBar({required this.scaleTypes, required this.controller});

  final List<ScaleTypeRow> scaleTypes;
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.elevatedSurface,
        // Traço fino fechando a barra, no lugar da sombra da AppBar.
        border: Border(bottom: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (var i = 0; i < scaleTypes.length; i++)
              _ScaleTab(
                label: scaleTypes[i].name,
                isSelected: i == controller.index,
                onPressed: () => controller.animateTo(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScaleTab extends StatelessWidget {
  const _ScaleTab({
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: (isSelected
                    ? AppTypography.subheadlineEmphasis
                    : AppTypography.subheadline)
                .copyWith(
              color: isSelected ? colors.tint : colors.secondaryLabel,
            ),
          ),
          const SizedBox(height: 6),
          // Sublinhado só na ativa; o inativo é transparente para que a altura
          // da barra não mude ao trocar de aba.
          Container(
            height: 2,
            width: 24,
            decoration: BoxDecoration(
              color: isSelected ? colors.tint : null,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}
