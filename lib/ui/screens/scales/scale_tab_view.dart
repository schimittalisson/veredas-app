import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/scales_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/widgets/empty_state.dart';

/// Conteúdo de uma aba de escala.
///
/// Conforme o `cadence` do tipo:
/// - `weekly`: navegador de semana (segunda a domingo, ISO).
/// - `monthly`: navegador de mês.
/// - `adhoc`: sem navegador; lista próximas + "Anteriores".
///
/// Conforme o tipo ter `slots` ou não:
/// - Com slots: tabela compacta (linhas = slots, células = responsável).
/// - Sem slots: lista por dia da semana.
class ScaleTabView extends ConsumerStatefulWidget {
  const ScaleTabView({
    required this.scaleType,
    required this.canEdit,
    super.key,
  });

  final ScaleTypeRow scaleType;
  final bool canEdit;

  @override
  ConsumerState<ScaleTabView> createState() => _ScaleTabViewState();
}

class _ScaleTabViewState extends ConsumerState<ScaleTabView> {
  late DateTime _periodStart;

  @override
  void initState() {
    super.initState();
    _periodStart = _startOfCurrentPeriod();
  }

  DateTime _startOfCurrentPeriod() {
    final now = DateTime.now();
    switch (widget.scaleType.cadence) {
      case 'weekly':
        // Segunda-feira da semana atual (ISO: DateTime.weekday = 1 = segunda).
        return DateTime(now.year, now.month, now.day - (now.weekday - 1));
      case 'monthly':
        return DateTime(now.year, now.month, 1);
      default:
        return now; // adhoc não usa período
    }
  }

  void _previousPeriod() {
    setState(() {
      switch (widget.scaleType.cadence) {
        case 'weekly':
          _periodStart = _periodStart.subtract(const Duration(days: 7));
        case 'monthly':
          _periodStart = DateTime(_periodStart.year, _periodStart.month - 1, 1);
      }
    });
  }

  void _nextPeriod() {
    setState(() {
      switch (widget.scaleType.cadence) {
        case 'weekly':
          _periodStart = _periodStart.add(const Duration(days: 7));
        case 'monthly':
          _periodStart = DateTime(_periodStart.year, _periodStart.month + 1, 1);
      }
    });
  }

  void _goToToday() {
    setState(() => _periodStart = _startOfCurrentPeriod());
  }

  @override
  Widget build(BuildContext context) {
    final cadence = widget.scaleType.cadence;

    if (cadence == 'adhoc') {
      return _AdhocView(scaleType: widget.scaleType);
    }

    return Column(
      children: [
        _PeriodNavigator(
          cadence: cadence,
          periodStart: _periodStart,
          onPrevious: _previousPeriod,
          onNext: _nextPeriod,
          onToday: _goToToday,
        ),
        const Divider(height: 1),
        Expanded(
          child: _PeriodBody(
            scaleType: widget.scaleType,
            periodStart: _periodStart,
            canEdit: widget.canEdit,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Navegador de período
// ---------------------------------------------------------------------------

class _PeriodNavigator extends StatelessWidget {
  const _PeriodNavigator({
    required this.cadence,
    required this.periodStart,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final String cadence;
  final DateTime periodStart;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    String label;
    if (cadence == 'weekly') {
      final end = periodStart.add(const Duration(days: 6));
      final fmt = DateFormat('d MMM', 'pt_BR');
      label = l.scales_week_of(fmt.format(periodStart), fmt.format(end));
    } else {
      label = DateFormat('MMMM y', 'pt_BR').format(periodStart);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrevious,
          ),
          Expanded(
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
          ),
          TextButton(onPressed: onToday, child: Text(l.scales_today)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Corpo do período (semana ou mês)
// ---------------------------------------------------------------------------

class _PeriodBody extends ConsumerWidget {
  const _PeriodBody({
    required this.scaleType,
    required this.periodStart,
    required this.canEdit,
  });

  final ScaleTypeRow scaleType;
  final DateTime periodStart;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cadence = scaleType.cadence;

    // Calcula o intervalo de datas.
    final from = periodStart;
    final to = cadence == 'weekly'
        ? periodStart.add(const Duration(days: 7))
        : DateTime(periodStart.year, periodStart.month + 1, 0);

    final query = (scaleTypeId: scaleType.id, from: from, to: to);
    final assignments = ref.watch(assignmentsProvider(query));
    final myCount = ref.watch(myAssignmentCountProvider(query)).value ?? 0;
    final currentUserId = ref.watch(currentUserIdProvider);

    return assignments.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_,_) => EmptyState(
        title: l.scales_no_assignments,
        icon: Icons.assignment_outlined,
      ),
      data: (data) {
        if (data.isEmpty) {
          return EmptyState(
            title: l.scales_no_assignments,
            icon: Icons.assignment_outlined,
            action: canEdit
                ? FilledButton.icon(
                    onPressed: () => context.push(
                      '${Routes.escalaAtribuicaoNovo}?scaleTypeId=${scaleType.id}',
                    ),
                    icon: const Icon(Icons.add),
                    label: Text(l.scales_mount),
                  )
                : null,
          );
        }

        return Column(
          children: [
            // Resumo "Você está escalado N×".
            if (currentUserId != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  l.scales_you_count(myCount),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            // Corpo: tabela com slots ou lista sem slots.
            Expanded(
              child: scaleType.slots.isNotEmpty
                  ? _SlotsTable(
                      scaleType: scaleType,
                      assignments: data,
                      periodStart: periodStart,
                      currentUserId: currentUserId,
                    )
                  : _SimpleList(
                      assignments: data,
                      periodStart: periodStart,
                      cadence: cadence,
                      currentUserId: currentUserId,
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tabela com slots (linhas = slots, células = responsável por dia)
// ---------------------------------------------------------------------------

class _SlotsTable extends StatelessWidget {
  const _SlotsTable({
    required this.scaleType,
    required this.assignments,
    required this.periodStart,
    required this.currentUserId,
  });

  final ScaleTypeRow scaleType;
  final List<ScaleAssignmentRow> assignments;
  final DateTime periodStart;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final days = scaleType.cadence == 'weekly' ? 7 : 1;
    final dayLabels = _dayLabels(periodStart, days);

    // Agrupa atribuições por (slot, dia).
    final bySlotAndDay = <String, Map<int, ScaleAssignmentRow>>{};
    for (final a in assignments) {
      final slot = a.slot ?? l.scales_slot_label;
      final dayIndex = a.startsOn.difference(periodStart).inDays;
      if (dayIndex < 0 || dayIndex >= days) continue;
      (bySlotAndDay[slot] ??= {})[dayIndex] = a;
    }

    final slots = scaleType.slots;

    return SingleChildScrollView(
      child: Card(
        margin: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              // Cabeçalho.
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      l.scales_slot_label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final label in dayLabels)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              // Linhas por slot.
              for (final slot in slots)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(slot, style: theme.textTheme.bodySmall),
                    ),
                    for (int day = 0; day < days; day++)
                      _AssignmentCell(
                        assignment: bySlotAndDay[slot]?[day],
                        currentUserId: currentUserId,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _dayLabels(DateTime start, int count) {
    final fmt = DateFormat.E('pt_BR');
    return [
      for (int i = 0; i < count; i++) fmt.format(start.add(Duration(days: i))),
    ];
  }
}

class _AssignmentCell extends StatelessWidget {
  const _AssignmentCell({required this.assignment, required this.currentUserId});

  final ScaleAssignmentRow? assignment;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (assignment == null) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Text(
          '—',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final isMe = assignment!.assigneeId == currentUserId;
    final name = assignment!.assigneeName ??
        assignment!.assigneeId ??
        l.scales_assignee_unknown;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: isMe
          ? BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isMe
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (isMe)
            Text(
              l.scales_you,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lista simples (sem slots) — por dia da semana
// ---------------------------------------------------------------------------

class _SimpleList extends StatelessWidget {
  const _SimpleList({
    required this.assignments,
    required this.periodStart,
    required this.cadence,
    required this.currentUserId,
  });

  final List<ScaleAssignmentRow> assignments;
  final DateTime periodStart;
  final String cadence;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = cadence == 'weekly' ? 7 : 1;

    // Agrupa por dia.
    final byDay = <int, List<ScaleAssignmentRow>>{};
    for (final a in assignments) {
      final dayIndex = a.startsOn.difference(periodStart).inDays;
      if (dayIndex < 0 || dayIndex >= days) continue;
      (byDay[dayIndex] ??= []).add(a);
    }

    final fmt = DateFormat.EEEE('pt_BR');

    return ListView(
      children: [
        for (int day = 0; day < days; day++)
          if (byDay[day] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                fmt.format(periodStart.add(Duration(days: day))),
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final a in byDay[day]!)
              _AssignmentListTile(
                assignment: a,
                isMe: a.assigneeId == currentUserId,
              ),
          ],
      ],
    );
  }
}

class _AssignmentListTile extends StatelessWidget {
  const _AssignmentListTile({required this.assignment, required this.isMe});

  final ScaleAssignmentRow assignment;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = assignment.assigneeName ??
        assignment.assigneeId ??
        l.scales_assignee_unknown;

    return Container(
      color: isMe ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        leading: Icon(
          Icons.person_outline,
          color: isMe
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(name),
        subtitle: assignment.task != null ? Text(assignment.task!) : null,
        trailing: isMe
            ? Chip(
                label: Text(l.scales_you),
                visualDensity: VisualDensity.compact,
              )
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// View adhoc (sem período — próximas + anteriores)
// ---------------------------------------------------------------------------

class _AdhocView extends ConsumerWidget {
  const _AdhocView({required this.scaleType});

  final ScaleTypeRow scaleType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final assignments = ref.watch(allAssignmentsProvider(scaleType.id));
    final currentUserId = ref.watch(currentUserIdProvider);

    return assignments.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_,_) => EmptyState(
        title: l.scales_no_assignments,
        icon: Icons.assignment_outlined,
      ),
      data: (data) {
        if (data.isEmpty) {
          return EmptyState(
            title: l.scales_no_assignments,
            icon: Icons.assignment_outlined,
          );
        }

        final now = DateTime.now();
        final upcoming = data.where((a) => a.startsOn.isAfter(now)).toList()
          ..sort((a, b) => a.startsOn.compareTo(b.startsOn));
        final past = data.where((a) => a.startsOn.isBefore(now)).toList()
          ..sort((a, b) => b.startsOn.compareTo(a.startsOn));

        return ListView(
          children: [
            for (final a in upcoming.take(10))
              _AssignmentListTile(
                assignment: a,
                isMe: a.assigneeId == currentUserId,
              ),
            if (past.isNotEmpty)
              ExpansionTile(
                title: Text('Anteriores'),
                children: past
                    .take(20)
                    .map((a) => _AssignmentListTile(
                          assignment: a,
                          isMe: a.assigneeId == currentUserId,
                        ))
                    .toList(),
              ),
          ],
        );
      },
    );
  }
}
