import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
/// `TabBar` **gerada dinamicamente** de `scale_types` (ordenada por `ordering`,
/// `is_active = true`), com `isScrollable: true`. Nunca hardcode as abas —
/// adicionar uma escala nova deve ser um `INSERT` no banco, não um release.
class ScalesScreen extends ConsumerWidget {
  const ScalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scaleTypes = ref.watch(activeScaleTypesProvider);

    // A TabBar precisa estar na mesma subárvore que o TabController, e o
    // controller só pode ser criado depois que sabemos quantas abas existem.
    // Por isso os estados sem abas têm um Scaffold próprio (AppBar sem
    // TabBar) e o caso com dados delega tudo — AppBar incluído — para
    // _ScalesBody, que é quem detém o controller.
    return scaleTypes.when(
      loading: () => _ScalesScaffold(title: l.tab_escalas, body: const LoadingState()),
      error: (_,_) => _ScalesScaffold(
        title: l.tab_escalas,
        body: EmptyState(
          title: l.scales_no_types,
          icon: Icons.assignment_outlined,
        ),
      ),
      data: (data) {
        if (data.isEmpty) {
          return _ScalesScaffold(
            title: l.tab_escalas,
            body: EmptyState(
              title: l.scales_no_types,
              icon: Icons.assignment_outlined,
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
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
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
    // recriado — senão o length diverge do número de abas e a TabBar quebra.
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
      // O FAB depende da aba ativa (cada escala tem seu próprio scaleTypeId
      // e sua própria permissão). Sem este listener, trocar de aba não
      // rebuilda e o FAB continua apontando para a escala anterior.
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
    final profile = ref.watch(currentProfileProvider).value;
    final managedIds = ref.watch(managedScaleTypeIdsProvider);

    final currentType = widget.scaleTypes[_tabController.index];
    final canEdit = _canEditScale(profile, currentType, managedIds);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.tab_escalas),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: widget.scaleTypes.map((t) => Tab(text: t.name)).toList(),
        ),
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              // Ver comentário em home_screen.dart: as 4 tabs coexistem.
              heroTag: 'fab-escalas',
              onPressed: () {
                context.push(
                  '${Routes.escalaAtribuicaoNovo}?scaleTypeId=${currentType.id}',
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: widget.scaleTypes
            .map((type) => ScaleTabView(
                  scaleType: type,
                  canEdit: _canEditScale(profile, type, managedIds),
                ))
            .toList(),
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
