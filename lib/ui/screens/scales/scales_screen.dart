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

    return Scaffold(
      appBar: AppBar(
        title: Text(l.tab_escalas),
        bottom: scaleTypes.when(
          loading: () => null,
          error: (_,_) => null,
          data: (data) => data.isEmpty
              ? null
              : TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: data.map((t) => Tab(text: t.name)).toList(),
                ),
        ),
      ),
      body: scaleTypes.when(
        loading: () => const LoadingState(),
        error: (_,_) => EmptyState(
          title: l.scales_no_types,
          icon: Icons.assignment_outlined,
        ),
        data: (data) {
          if (data.isEmpty) {
            return EmptyState(
              title: l.scales_no_types,
              icon: Icons.assignment_outlined,
            );
          }
          return _ScalesBody(scaleTypes: data);
        },
      ),
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
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.scaleTypes.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).value;
    final managedIds = ref.watch(managedScaleTypeIdsProvider);

    final currentType = widget.scaleTypes[_tabController.index];
    final canEdit = _canEditScale(profile, currentType, managedIds);

    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton(
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
            .map((type) => ScaleTabView(scaleType: type))
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
