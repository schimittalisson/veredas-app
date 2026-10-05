import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/local/tables.dart' show kScheduleEted;
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/admin_providers.dart';
import 'package:veredas/providers/agenda_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';

/// Tela de Responsáveis por escala — uma seção agrupada por scale_type, e no
/// topo a dos líderes do cronograma da ETED.
///
/// Os líderes da ETED moram aqui, e não numa tela própria, porque são o mesmo
/// gesto: "quem pode editar isto". Uma entrada a mais no menu de
/// Administração para uma seção só seria mais um lugar para procurar.
///
/// Lista os responsáveis atuais com botão de remover, e "Adicionar
/// responsável" abrindo um seletor de obreiros aprovados.
///
/// O `ExpansionTile` do Material saiu: como ele já vinha `initiallyExpanded`,
/// nunca houve colapso de verdade. A seção agrupada do iOS entrega o mesmo
/// agrupamento com o cabeçalho no lugar do título expansível.
class ResponsaveisScreen extends ConsumerWidget {
  const ResponsaveisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;
    final scaleTypes = ref.watch(allScaleTypesProvider);
    final managersByType = ref.watch(scaleManagersByTypeProvider);
    final profiles = ref.watch(approvedProfilesProvider);
    final etedLeaderIds = [
      for (final m
          in ref.watch(scheduleManagersProvider).value ??
              const <ScheduleManagerRow>[])
        if (m.schedule == kScheduleEted) m.userId,
    ];
    final admin = ref.read(adminServiceProvider);

    final etedSection = _ManagersSection(
      header: l.admin_eted_leaders,
      footer: l.admin_eted_leaders_footer,
      managerIds: etedLeaderIds,
      profiles: profiles,
      onAdd: (userId) =>
          admin.addScheduleManager(schedule: kScheduleEted, userId: userId),
      onRemove: (userId) =>
          admin.removeScheduleManager(schedule: kScheduleEted, userId: userId),
    );

    return CupertinoPageScaffold(
      backgroundColor: colors.groupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(l.admin_scale_managers),
        backgroundColor: colors.elevatedSurface,
      ),
      child: SafeArea(
        bottom: false,
        child: scaleTypes.when(
          loading: () => const LoadingState(),
          // Sem tipos de escala, a seção da ETED continua: ela não depende
          // deles, e o estado vazio a esconderia.
          error: (_, _) => ListView(children: [etedSection]),
          data: (types) {
            return ListView(
              children: [
                etedSection,
                if (types.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: EmptyState(
                      title: l.admin_managers_no_types,
                      icon: CupertinoIcons.person_badge_plus,
                    ),
                  ),
                for (final type in types)
                  _ManagersSection(
                    header: type.name,
                    managerIds: [
                      for (final m in managersByType[type.id] ?? const [])
                        m.userId,
                    ],
                    profiles: profiles,
                    onAdd: (userId) => admin.addScaleManager(
                      scaleTypeId: type.id,
                      userId: userId,
                    ),
                    onRemove: (userId) => admin.removeScaleManager(
                      scaleTypeId: type.id,
                      userId: userId,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ManagersSection
// ---------------------------------------------------------------------------

/// Uma lista de "quem pode editar": os responsáveis de um tipo de escala ou
/// os líderes de um cronograma. Só muda o que [onAdd] e [onRemove] chamam.
class _ManagersSection extends StatelessWidget {
  const _ManagersSection({
    required this.header,
    required this.managerIds,
    required this.profiles,
    required this.onAdd,
    required this.onRemove,
    this.footer,
  });

  final String header;
  final String? footer;
  final List<String> managerIds;
  final List<ProfileRow> profiles;
  final Future<void> Function(String userId) onAdd;
  final Future<void> Function(String userId) onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    // Nomes dos responsáveis atuais.
    final managerProfiles = <ProfileRow>[];
    for (final id in managerIds) {
      final p = profiles.where((p) => p.id == id).firstOrNull;
      if (p != null) managerProfiles.add(p);
    }

    return CupertinoListSection.insetGrouped(
      backgroundColor: colors.groupedBackground,
      separatorColor: colors.separator,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      header: Text(
        header,
        style: AppTypography.sectionHeader.copyWith(color: colors.tint),
      ),
      footer: footer == null
          ? null
          : Text(
              footer!,
              style: AppTypography.footnote.copyWith(
                color: colors.secondaryLabel,
              ),
            ),
      children: [
        if (managerProfiles.isEmpty)
          CupertinoListTile(
            title: Text(
              l.admin_managers_none,
              style: AppTypography.footnote.copyWith(
                color: colors.secondaryLabel,
              ),
            ),
          ),
        ...managerProfiles.map(
          (p) => CupertinoListTile(
            leading: _Avatar(name: p.fullName),
            title: Text(
              p.fullName,
              style: AppTypography.body.copyWith(color: colors.label),
            ),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              // `tooltip` é do Material; o rótulo vira semântica.
              onPressed: () async {
                try {
                  await onRemove(p.id);
                } catch (e) {
                  if (context.mounted) {
                    showAppToast(context, e.toString(), isError: true);
                  }
                }
              },
              child: Semantics(
                label: l.admin_managers_remove,
                button: true,
                child: Icon(
                  CupertinoIcons.minus_circle,
                  size: 22,
                  color: colors.destructive,
                ),
              ),
            ),
          ),
        ),
        CupertinoListTile(
          leading: Icon(CupertinoIcons.add_circled, color: colors.tint),
          title: Text(
            l.admin_managers_add,
            style: AppTypography.body.copyWith(color: colors.tint),
          ),
          onTap: () => _showAddPicker(context),
        ),
      ],
    );
  }

  /// Seletor de obreiros.
  ///
  /// Vira uma folha de ações em vez de um alerta com lista dentro: no iOS a
  /// escolha entre N itens sobe da base da tela, e a folha já rola sozinha
  /// quando a lista passa da altura disponível — o que o `AlertDialog` com
  /// `ListView(shrinkWrap: true)` resolvia na unha.
  Future<void> _showAddPicker(BuildContext context) async {
    final l = AppLocalizations.of(context);

    // Obreiros aprovados que ainda não são responsáveis.
    final currentManagerIds = managerIds.toSet();
    final candidates = profiles
        .where((p) => !currentManagerIds.contains(p.id))
        .toList();

    if (candidates.isEmpty) {
      showAppToast(context, l.admin_managers_select);
      return;
    }

    final userId = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(l.admin_managers_add),
        actions: candidates
            .map(
              (p) => CupertinoActionSheetAction(
                onPressed: () => Navigator.of(sheetContext).pop(p.id),
                child: Text(p.fullName),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          isDefaultAction: true,
          child: Text(l.action_cancel),
        ),
      ),
    );

    if (userId == null) return;

    try {
      await onAdd(userId);
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, e.toString(), isError: true);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// _Avatar
// ---------------------------------------------------------------------------

/// Círculo com as iniciais — o `CircleAvatar` é do Material.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // 28px é o `leadingSize` padrão do CupertinoListTile — sair dele
    // desalinharia os separadores da seção.
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.tintContainer,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials(name),
        style: AppTypography.caption.copyWith(
          color: colors.onTintContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  final first = parts.first.substring(0, 1);
  if (parts.length == 1) return first.toUpperCase();
  return (first + parts.last.substring(0, 1)).toUpperCase();
}
