import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/admin_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';

/// Administração das escalas — as abas da tela Escalas.
///
/// Existe para que criar, renomear, reordenar ou remover uma escala seja
/// trabalho do admin dentro do app: `scale_types` sempre foi dado, não código,
/// mas até aqui só o SQL Editor alcançava a tabela.
///
/// Lista **todas** as escalas, inclusive as ocultas (`is_active = false`), que
/// não aparecem na tela Escalas — é aqui que elas voltam a existir.
class EscalasScreen extends ConsumerWidget {
  const EscalasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final scaleTypes = ref.watch(allScaleTypesProvider);

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.admin_scales),
        backgroundColor: colors.elevatedSurface,
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => context.push(Routes.adminEscalaNova),
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: scaleTypes.when(
          loading: () => const LoadingState(),
          error: (_, _) => EmptyState(
            title: l.admin_scales_empty,
            icon: CupertinoIcons.list_bullet,
          ),
          data: (types) {
            if (types.isEmpty) {
              return EmptyState(
                title: l.admin_scales_empty,
                icon: CupertinoIcons.list_bullet,
              );
            }
            return _ReorderableList(types: types);
          },
        ),
      ),
    );
  }
}

/// A lista arrastável.
///
/// `ReorderableList` vem de `package:flutter/widgets.dart`, e não o
/// `ReorderableListView` do Material: este arquivo não importa Material, como
/// o resto do app depois da migração para Cupertino.
///
/// A ordem fica num estado local em vez de sair direto do provider porque o
/// arrasto precisa de resposta no mesmo quadro. A escrita é otimista e o
/// stream do drift confirma logo depois; sem o estado local, o item voltaria
/// para a posição antiga entre o soltar e a emissão do stream.
class _ReorderableList extends ConsumerStatefulWidget {
  const _ReorderableList({required this.types});

  final List<ScaleTypeRow> types;

  @override
  ConsumerState<_ReorderableList> createState() => _ReorderableListState();
}

class _ReorderableListState extends ConsumerState<_ReorderableList> {
  late List<ScaleTypeRow> _types;

  @override
  void initState() {
    super.initState();
    _types = widget.types;
  }

  @override
  void didUpdateWidget(_ReorderableList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // O sync (ou a própria escrita otimista) trouxe outra lista: adota. Só o
    // arrasto em andamento tem preferência, e ele já terminou aqui.
    if (widget.types != oldWidget.types) {
      _types = widget.types;
    }
  }

  /// `onReorderItem`, e não o `onReorder` (deprecado desde o Flutter 3.41):
  /// o novo já entrega `toIndex` com o item removido da lista, poupando o
  /// `if (newIndex > oldIndex) newIndex -= 1` que era erro de 1 clássico aqui.
  Future<void> _onReorder(int fromIndex, int toIndex) async {
    final reordered = [..._types];
    final moved = reordered.removeAt(fromIndex);
    reordered.insert(toIndex, moved);
    setState(() => _types = reordered);

    try {
      await ref
          .read(scalesRepositoryProvider)
          .reorderScaleTypes([for (final t in reordered) t.id]);
    } catch (e) {
      if (mounted) {
        showAppToast(context, e.toString(), isError: true);
        setState(() => _types = widget.types);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            l.admin_scales_reorder_hint,
            style:
                AppTypography.footnote.copyWith(color: colors.secondaryLabel),
          ),
        ),
        Expanded(
          child: ReorderableList(
            itemCount: _types.length,
            onReorderItem: _onReorder,
            itemBuilder: (context, index) {
              final type = _types[index];
              return _ScaleTypeTile(
                // A key é por id, não por índice: com índice o arrasto
                // reaproveitaria o estado da linha errada.
                key: ValueKey(type.id),
                index: index,
                type: type,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ScaleTypeTile extends StatelessWidget {
  const _ScaleTypeTile({
    required this.index,
    required this.type,
    super.key,
  });

  final int index;
  final ScaleTypeRow type;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    final details = [
      _cadenceLabel(l, type.cadence),
      if (type.slots.isNotEmpty) type.slots.join(', '),
      if (!type.isActive) l.admin_scales_hidden,
    ].join(' · ');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: CupertinoListTile(
        backgroundColor: colors.surface,
        title: Text(
          type.name,
          style: AppTypography.body.copyWith(
            // Escala oculta fica apagada: ela existe, mas ninguém a vê na
            // tela Escalas.
            color: type.isActive ? colors.label : colors.secondaryLabel,
          ),
        ),
        subtitle: Text(
          details,
          style: AppTypography.footnote.copyWith(color: colors.secondaryLabel),
        ),
        trailing: ReorderableDragStartListener(
          index: index,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Icon(
              CupertinoIcons.line_horizontal_3,
              color: colors.tertiaryLabel,
            ),
          ),
        ),
        onTap: () => context.push('${Routes.adminEscalaEditar}?id=${type.id}'),
      ),
    );
  }
}

/// Rótulo da cadência guardada em `scale_types.cadence`.
String _cadenceLabel(AppLocalizations l, String cadence) => switch (cadence) {
      'monthly' => l.admin_scales_cadence_monthly,
      'adhoc' => l.admin_scales_cadence_adhoc,
      _ => l.admin_scales_cadence_weekly,
    };
