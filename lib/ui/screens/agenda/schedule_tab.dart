import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/agenda_providers.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';

/// Aba Cronograma da Agenda — a "planilha" semanal.
///
/// `SegmentedButton` alterna entre **Grade** (7 colunas com scroll horizontal)
/// e **Lista por dia** (`ExpansionTile` por dia — mais confortável no celular).
class ScheduleTab extends ConsumerStatefulWidget {
  const ScheduleTab({super.key});

  @override
  ConsumerState<ScheduleTab> createState() => _ScheduleTabState();
}

enum _ScheduleView { grid, list }

class _ScheduleTabState extends ConsumerState<ScheduleTab> {
  _ScheduleView _view = _ScheduleView.grid;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final slots = ref.watch(weeklySlotsProvider);

    return Column(
      children: [
        // SegmentedButton para alternar Grade/Lista.
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_ScheduleView>(
              segments: [
                ButtonSegment(
                  value: _ScheduleView.grid,
                  label: Text(l.agenda_view_grid),
                  icon: const Icon(Icons.grid_on_outlined),
                ),
                ButtonSegment(
                  value: _ScheduleView.list,
                  label: Text(l.agenda_view_list),
                  icon: const Icon(Icons.list_outlined),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (set) =>
                  setState(() => _view = set.first),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: slots.when(
            loading: () => const LoadingState(),
            error: (_,_) => EmptyState(
              title: l.agenda_no_schedule,
              icon: Icons.calendar_view_week_outlined,
            ),
            data: (data) {
              if (data.isEmpty) {
                return EmptyState(
                  title: l.agenda_no_schedule,
                  icon: Icons.calendar_view_week_outlined,
                );
              }
              return _view == _ScheduleView.grid
                  ? _WeeklyGrid(slots: data)
                  : _WeeklyList(slots: data);
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Grade semanal — "estilo planilha" com scroll horizontal.
// ---------------------------------------------------------------------------

class _WeeklyGrid extends StatelessWidget {
  const _WeeklyGrid({required this.slots});

  final List<WeeklySlotRow> slots;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    // Filtra slots ativos e agrupa por dia.
    final byDay = <int, List<WeeklySlotRow>>{};
    for (final slot in slots) {
      if (!slot.isActive) continue;
      (byDay[slot.weekday] ??= []).add(slot);
    }

    // Calcula o range de horas: do menor startsAt ao maior endsAt.
    int minMinutes = 24 * 60;
    int maxMinutes = 0;
    for (final slot in slots) {
      if (!slot.isActive) continue;
      if (slot.startsAtMinutes < minMinutes) minMinutes = slot.startsAtMinutes;
      final end = slot.endsAtMinutes ?? slot.startsAtMinutes + 60;
      if (end > maxMinutes) maxMinutes = end;
    }
    // Arredonda para a hora cheia mais próxima.
    minMinutes = (minMinutes ~/ 60) * 60;
    maxMinutes = ((maxMinutes + 59) ~/ 60) * 60;

    final hours = <int>[];
    for (int m = minMinutes; m < maxMinutes; m += 60) {
      hours.add(m);
    }

    final dayLabels = [
      l.agenda_weekday_mon,
      l.agenda_weekday_tue,
      l.agenda_weekday_wed,
      l.agenda_weekday_thu,
      l.agenda_weekday_fri,
      l.agenda_weekday_sat,
      l.agenda_weekday_sun,
    ];

    final theme = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Coluna fixa de horários (56 dp).
          SizedBox(
            width: 56,
            child: Column(
              children: [
                // Célula de canto (vazia, alinha com o cabeçalho dos dias).
                SizedBox(
                  height: 40,
                  child: Center(
                    child: Text(
                      'h',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
                ...hours.map((m) => _HourCell(minutes: m)),
              ],
            ),
          ),
          // Grade scrollável horizontalmente.
          //
          // O Expanded é obrigatório: num Row, um filho não-flex recebe
          // largura ilimitada, então o SingleChildScrollView se dimensionaria
          // pelo conteúdo (7 × 96 dp). Viewport do tamanho do conteúdo = nada
          // para rolar — a grade estourava para fora da tela em vez de
          // arrastar. Com Expanded ele fica limitado à largura restante e o
          // scroll passa a funcionar.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabeçalho dos dias.
                  Row(
                    children: [
                      for (int day = 1; day <= 7; day++)
                        SizedBox(
                          width: 96,
                          height: 40,
                          child: Center(
                            child: Text(
                              dayLabels[day - 1],
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Linhas de hora.
                  for (final hour in hours)
                    Row(
                      children: [
                        for (int day = 1; day <= 7; day++)
                          _DayHourCell(
                            day: day,
                            hourMinutes: hour,
                            slots: byDay[day] ?? const [],
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HourCell extends StatelessWidget {
  const _HourCell({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final h = minutes ~/ 60;
    return SizedBox(
      height: 56,
      child: Center(
        child: Text(
          '${h.toString().padLeft(2, '0')}h',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _DayHourCell extends StatelessWidget {
  const _DayHourCell({
    required this.day,
    required this.hourMinutes,
    required this.slots,
  });

  final int day;
  final int hourMinutes;
  final List<WeeklySlotRow> slots;

  @override
  Widget build(BuildContext context) {
    // Encontra o slot que cobre esta hora.
    final slot = slots.where((s) {
      final end = s.endsAtMinutes ?? s.startsAtMinutes + 60;
      return s.startsAtMinutes <= hourMinutes && end > hourMinutes;
    }).firstOrNull;

    if (slot == null) {
      return Container(
        width: 96,
        height: 56,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    // Cor baseada na categoria — usa o ColorScheme, não cores hardcodadas.
    final color = _categoryColor(context, slot.category);

    return GestureDetector(
      onTap: () => _showDetails(context, slot),
      child: Container(
        width: 96,
        height: 56,
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 1),
        ),
        child: Text(
          slot.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Color _categoryColor(BuildContext context, String? category) {
    if (category == null) {
      return Theme.of(context).colorScheme.primaryContainer;
    }
    final c = category.toLowerCase();
    final scheme = Theme.of(context).colorScheme;
    if (c.contains('culto') || c.contains('reuniao')) {
      return scheme.primaryContainer;
    }
    if (c.contains('treinamento') || c.contains('curso')) {
      return scheme.tertiaryContainer;
    }
    if (c.contains('viagem') || c.contains('saida')) {
      return scheme.secondaryContainer;
    }
    return scheme.primaryContainer;
  }

  void _showDetails(BuildContext context, WeeklySlotRow slot) {
    final start = TimeOfDay(
      hour: slot.startsAtMinutes ~/ 60,
      minute: slot.startsAtMinutes % 60,
    );
    final end = slot.endsAtMinutes != null
        ? TimeOfDay(
            hour: slot.endsAtMinutes! ~/ 60,
            minute: slot.endsAtMinutes! % 60,
          )
        : null;

    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(slot.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              end != null
                  ? '${start.format(context)} – ${end.format(context)}'
                  : start.format(context),
            ),
            if (slot.location != null && slot.location!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 16),
                  const SizedBox(width: 4),
                  Text(slot.location!),
                ],
              ),
            ],
            if (slot.notes != null && slot.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(slot.notes!),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lista por dia — ExpansionTile por dia da semana.
// ---------------------------------------------------------------------------

class _WeeklyList extends StatelessWidget {
  const _WeeklyList({required this.slots});

  final List<WeeklySlotRow> slots;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final dayLabels = [
      l.agenda_weekday_mon,
      l.agenda_weekday_tue,
      l.agenda_weekday_wed,
      l.agenda_weekday_thu,
      l.agenda_weekday_fri,
      l.agenda_weekday_sat,
      l.agenda_weekday_sun,
    ];

    final byDay = <int, List<WeeklySlotRow>>{};
    for (final slot in slots) {
      if (!slot.isActive) continue;
      (byDay[slot.weekday] ??= []).add(slot);
    }

    return ListView(
      children: [
        for (int day = 1; day <= 7; day++)
          ExpansionTile(
            title: Text(dayLabels[day - 1]),
            initiallyExpanded: day == DateTime.now().weekday,
            children: (byDay[day] ?? const [])
                .map((slot) => _SlotListTile(slot: slot))
                .toList(),
          ),
      ],
    );
  }
}

class _SlotListTile extends StatelessWidget {
  const _SlotListTile({required this.slot});

  final WeeklySlotRow slot;

  @override
  Widget build(BuildContext context) {
    final start = TimeOfDay(
      hour: slot.startsAtMinutes ~/ 60,
      minute: slot.startsAtMinutes % 60,
    );
    final end = slot.endsAtMinutes != null
        ? TimeOfDay(
            hour: slot.endsAtMinutes! ~/ 60,
            minute: slot.endsAtMinutes! % 60,
          )
        : null;

    return ListTile(
      leading: const Icon(Icons.schedule, size: 20),
      title: Text(slot.title),
      subtitle: Text(
        end != null
            ? '${start.format(context)} – ${end.format(context)}'
            : start.format(context),
      ),
      onTap: () {
        // Reutiliza o _showDetails do _DayHourCell via showModalBottomSheet.
        // TODO: extrair para um widget compartilhado.
      },
    );
  }
}
