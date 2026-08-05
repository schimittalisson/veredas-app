import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/agenda_providers.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';

/// Formata minutos desde a meia-noite como `HH:mm`.
///
/// Substitui `TimeOfDay.format(context)`, que é do Material e depende de
/// `MaterialLocalizations` — inexistente sob `CupertinoApp`. Como o app é
/// pt-BR (relógio de 24 h), a formatação fixa dá exatamente o mesmo resultado
/// que o `TimeOfDay` dava antes.
String _formatMinutes(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Aba Cronograma da Agenda — a "planilha" semanal.
///
/// `CupertinoSlidingSegmentedControl` alterna entre **Grade** (7 colunas com
/// scroll horizontal) e **Lista por dia** (seções recolhíveis — mais
/// confortável no celular).
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
    final colors = context.colors;
    final slots = ref.watch(weeklySlotsProvider);

    return Column(
      children: [
        // Controle Grade/Lista. Fica à esquerda e com largura intrínseca de
        // propósito: o segmented control de Eventos/Cronograma logo acima
        // ocupa a linha inteira, e dois controles idênticos empilhados
        // confundiriam qual deles manda em quê.
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: CupertinoSlidingSegmentedControl<_ScheduleView>(
              groupValue: _view,
              backgroundColor: colors.fill,
              thumbColor: colors.surface,
              onValueChanged: (value) {
                if (value != null) setState(() => _view = value);
              },
              children: {
                _ScheduleView.grid: _ViewSegment(
                  icon: CupertinoIcons.square_grid_2x2,
                  label: l.agenda_view_grid,
                ),
                _ScheduleView.list: _ViewSegment(
                  icon: CupertinoIcons.list_bullet,
                  label: l.agenda_view_list,
                ),
              },
            ),
          ),
        ),
        Container(height: 0.5, color: colors.separator),
        Expanded(
          child: slots.when(
            loading: () => const LoadingState(),
            error: (_,_) => EmptyState(
              title: l.agenda_no_schedule,
              icon: CupertinoIcons.calendar,
            ),
            data: (data) {
              if (data.isEmpty) {
                return EmptyState(
                  title: l.agenda_no_schedule,
                  icon: CupertinoIcons.calendar,
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

/// Conteúdo de um segmento: ícone + rótulo.
class _ViewSegment extends StatelessWidget {
  const _ViewSegment({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.label),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.subheadlineEmphasis
                .copyWith(color: colors.label),
          ),
        ],
      ),
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

    final colors = context.colors;

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
                      style: AppTypography.caption
                          .copyWith(color: colors.secondaryLabel),
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
                              style: AppTypography.footnoteEmphasis
                                  .copyWith(color: colors.label),
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
          style: AppTypography.footnote
              .copyWith(color: context.colors.secondaryLabel),
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
    final colors = context.colors;

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
            color: colors.separator,
            width: 0.5,
          ),
        ),
      );
    }

    final category = slot.category ?? '';
    // `accentFor`/`accentContainerFor` derivam uma cor estável da string da
    // categoria (ver AppColors). Trocamos a cadeia de `if`s por elas porque
    // no Cupertino não existe `tertiaryContainer`: mapear os três ramos para
    // `tintContainer` deixaria todas as categorias com a mesma cor, perdendo
    // justamente a informação que a cor carrega na grade. O par
    // container/onContainer já tem contraste verificado em AA.
    final fill = category.isEmpty
        ? colors.tintContainer
        : colors.accentContainerFor(category);
    final border =
        category.isEmpty ? colors.tint : colors.accentFor(category);
    final onFill = category.isEmpty
        ? colors.onTintContainer
        : colors.onAccentContainerFor(category);

    return GestureDetector(
      onTap: () => _showSlotDetails(context, slot),
      child: Container(
        width: 96,
        height: 56,
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border, width: 1),
        ),
        child: Text(
          slot.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(color: onFill),
        ),
      ),
    );
  }
}

/// Folha de detalhes de um slot.
///
/// `showModalBottomSheet` do Material vira `showCupertinoModalPopup`: no iOS a
/// folha sobe do rodapé com cantos arredondados e fundo de superfície, sem a
/// sombra/elevação do Material.
void _showSlotDetails(BuildContext context, WeeklySlotRow slot) {
  final colors = context.colors;
  final start = _formatMinutes(slot.startsAtMinutes);
  final end = slot.endsAtMinutes != null
      ? _formatMinutes(slot.endsAtMinutes!)
      : null;

  showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slot.title,
                style: AppTypography.headline.copyWith(color: colors.label),
              ),
              const SizedBox(height: 8),
              Text(
                end != null ? '$start – $end' : start,
                style: AppTypography.subheadline
                    .copyWith(color: colors.secondaryLabel),
              ),
              if (slot.location != null && slot.location!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.location,
                      size: 16,
                      color: colors.secondaryLabel,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      slot.location!,
                      style: AppTypography.subheadline
                          .copyWith(color: colors.label),
                    ),
                  ],
                ),
              ],
              if (slot.notes != null && slot.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  slot.notes!,
                  style:
                      AppTypography.subheadline.copyWith(color: colors.label),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Lista por dia — seções recolhíveis por dia da semana.
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
          _DaySection(
            title: dayLabels[day - 1],
            initiallyExpanded: day == DateTime.now().weekday,
            children: (byDay[day] ?? const [])
                .map((slot) => _SlotListTile(slot: slot))
                .toList(),
          ),
      ],
    );
  }
}

/// Seção recolhível de um dia.
///
/// Não existe `ExpansionTile` no Cupertino, então o comportamento é refeito à
/// mão: uma linha de cabeçalho com chevron que gira e os filhos abaixo. O
/// estado começa aberto no dia de hoje, como antes.
class _DaySection extends StatefulWidget {
  const _DaySection({
    required this.title,
    required this.initiallyExpanded,
    required this.children,
  });

  final String title;
  final bool initiallyExpanded;
  final List<Widget> children;

  @override
  State<_DaySection> createState() => _DaySectionState();
}

class _DaySectionState extends State<_DaySection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          // opaque: sem isso o toque só valeria em cima do texto, não na
          // faixa inteira da linha.
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style:
                        AppTypography.headline.copyWith(color: colors.label),
                  ),
                ),
                Icon(
                  _expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 18,
                  color: colors.secondaryLabel,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...widget.children,
        Container(height: 0.5, color: colors.separator),
      ],
    );
  }
}

class _SlotListTile extends StatelessWidget {
  const _SlotListTile({required this.slot});

  final WeeklySlotRow slot;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final start = _formatMinutes(slot.startsAtMinutes);
    final end = slot.endsAtMinutes != null
        ? _formatMinutes(slot.endsAtMinutes!)
        : null;

    return CupertinoListTile(
      backgroundColor: colors.surface,
      leading: Icon(
        CupertinoIcons.clock,
        size: 20,
        color: colors.secondaryLabel,
      ),
      title: Text(
        slot.title,
        style: AppTypography.body.copyWith(color: colors.label),
      ),
      subtitle: Text(
        end != null ? '$start – $end' : start,
        style: AppTypography.footnote.copyWith(color: colors.secondaryLabel),
      ),
      onTap: () {
        // Continua sem ação, como antes da migração. O _showSlotDetails já
        // está extraído aqui no arquivo; falta decidir se a lista abre a
        // mesma folha ou vai direto para o editor.
        // TODO: extrair para um widget compartilhado.
      },
    );
  }
}
