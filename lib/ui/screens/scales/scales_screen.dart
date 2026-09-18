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
import 'package:veredas/ui/screens/scales/laundry_tab.dart';
import 'package:veredas/ui/screens/scales/scale_tab_view.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';
import 'package:veredas/ui/widgets/pull_to_refresh.dart';

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
      loading: () => _ScalesScaffold(
        title: l.tab_escalas,
        body: const RefreshableBox(child: LoadingState()),
      ),
      error: (_,_) => _ScalesScaffold(
        title: l.tab_escalas,
        body: RefreshableBox(
          child: EmptyState(
            title: l.scales_no_types,
            icon: CupertinoIcons.doc_text,
          ),
        ),
      ),
      // Mesmo sem nenhum tipo de escala cadastrado o corpo monta: a aba
      // Lavanderia é fixa e precisa existir de qualquer forma. O estado vazio
      // de "nenhuma escala" passou a ser tratado dentro de cada aba.
      data: (data) => _ScalesBody(scaleTypes: data),
    );
  }
}

// ---------------------------------------------------------------------------
// _ScalesScaffold
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// _ScalesBody
// ---------------------------------------------------------------------------

class _ScalesBody extends ConsumerStatefulWidget {
  const _ScalesBody({required this.scaleTypes});

  final List<ScaleTypeRow> scaleTypes;

  @override
  ConsumerState<_ScalesBody> createState() => _ScalesBodyState();
}

class _ScalesBodyState extends ConsumerState<_ScalesBody>
    with TickerProviderStateMixin {
  late TabController _tabController;

  /// A escala aberta, guardada por **id** e não por posição.
  ///
  /// A ordem das abas é editável pelo admin (`/admin/escalas`) e chega por
  /// sync a qualquer momento. Guardando só o índice, uma reordenação feita em
  /// outro aparelho trocaria a escala que está na tela debaixo do dedo de quem
  /// está olhando.
  String? _selectedTypeId;

  @override
  void initState() {
    super.initState();
    _tabController = _createController();
    _selectedTypeId = widget.scaleTypes.firstOrNull?.id;
  }

  @override
  void didUpdateWidget(_ScalesBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    final target = _indexOfSelected();

    // As escalas vêm do sync: uma nova pode aparecer (ou ser desativada) a
    // qualquer momento. O TabController tem length fixo, então precisa ser
    // recriado — senão o length diverge do número de abas e a troca quebra.
    if (widget.scaleTypes.length != oldWidget.scaleTypes.length) {
      _tabController
        ..removeListener(_onTabChanged)
        ..dispose();
      _tabController = _createController(initialIndex: target);
      _selectedTypeId = target < widget.scaleTypes.length
          ? widget.scaleTypes[target].id
          : null;
    } else if (target != _tabController.index) {
      // Mesma quantidade, ordem diferente: segue a escala, não a posição.
      _tabController.index = target;
    }
  }

  /// Posição da escala aberta na lista atual. Se ela sumiu (desativada ou
  /// excluída), cai na posição mais próxima da que ocupava.
  int _indexOfSelected() {
    // A tela só monta este corpo com pelo menos uma escala, mas o clamp abaixo
    // precisa de um limite válido — uma lista vazia daria clamp(0, -1).
    if (widget.scaleTypes.isEmpty) return 0;
    final last = widget.scaleTypes.length - 1;
    final index =
        widget.scaleTypes.indexWhere((t) => t.id == _selectedTypeId);
    return index >= 0 ? index : _tabController.index.clamp(0, last);
  }

  TabController _createController({int initialIndex = 0}) {
    return TabController(
      // +1: a Lavanderia é uma aba fixa, sempre no fim, depois das escalas
      // que vêm do cadastro.
      length: widget.scaleTypes.length + 1,
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
    if (!mounted) return;
    // Na aba fixa da Lavanderia não há escala que memorizar; o setState ainda
    // é necessário para a barra repintar e o botão do canto sumir.
    if (_isLaundryTab || widget.scaleTypes.isEmpty) {
      setState(() {});
      return;
    }
    final index = _tabController.index.clamp(0, widget.scaleTypes.length - 1);
    setState(() => _selectedTypeId = widget.scaleTypes[index].id);
  }

  /// A aba aberta é a Lavanderia (a última).
  bool get _isLaundryTab => _tabController.index >= widget.scaleTypes.length;

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

    // Na Lavanderia não há escala ativa: o botão de "nova atribuição" do canto
    // não se aplica, e indexar a lista pelo índice da aba estouraria.
    final currentType = _isLaundryTab || widget.scaleTypes.isEmpty
        ? null
        : widget.scaleTypes[_tabController.index];
    final canEdit = currentType != null &&
        _canEditScale(profile, currentType, managedIds);

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
        // `bottom` fica ligado: o RootScaffold soma o espaço da barra
        // flutuante ao MediaQuery, e é isso que impede o último item da
        // lista de ficar escondido atrás dela.
        child: Column(
          children: [
            _ScaleTabBar(
              scaleTypes: widget.scaleTypes,
              controller: _tabController,
              laundryLabel: l.laundry_tab,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  ...widget.scaleTypes.map((type) => ScaleTabView(
                        scaleType: type,
                        canEdit: _canEditScale(profile, type, managedIds),
                      )),
                  const LaundryTab(),
                ],
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

// ---------------------------------------------------------------------------
// _ScaleTabBar
// ---------------------------------------------------------------------------

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
  const _ScaleTabBar({
    required this.scaleTypes,
    required this.controller,
    required this.laundryLabel,
  });

  final List<ScaleTypeRow> scaleTypes;
  final TabController controller;

  /// Rótulo da aba fixa, sempre desenhada depois das escalas do cadastro.
  final String laundryLabel;

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
            // A Lavanderia fecha a barra. Não vem do cadastro de escalas, mas
            // ocupa o mesmo lugar na cabeça de quem usa: "onde eu me inscrevo".
            _ScaleTab(
              label: laundryLabel,
              isSelected: controller.index == scaleTypes.length,
              onPressed: () => controller.animateTo(scaleTypes.length),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ScaleTab
// ---------------------------------------------------------------------------

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
