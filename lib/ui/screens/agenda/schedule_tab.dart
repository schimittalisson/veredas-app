import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/agenda_providers.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/widgets/app_toast.dart';
import 'package:veredas/ui/widgets/confirm_dialog.dart';
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

/// Altura de uma faixa de uma hora. Define a escala da grade inteira.
const double _kHourHeight = 56;

/// Largura de uma coluna de dia.
const double _kDayWidth = 96;

/// Largura da régua de horários à esquerda.
const double _kGutterWidth = 56;

/// Altura do cabeçalho com os nomes dos dias.
const double _kHeaderHeight = 40;

/// Um slot já resolvido em coordenadas de tela.
///
/// [column] e [columnCount] resolvem sobreposição: quando dois compromissos
/// dividem o mesmo horário, cada um ocupa uma fração da largura do dia, em vez
/// de um esconder o outro.
class _LaidOutSlot {
  const _LaidOutSlot({
    required this.slot,
    required this.top,
    required this.height,
    required this.column,
    required this.columnCount,
  });

  final WeeklySlotRow slot;
  final double top;
  final double height;
  final int column;
  final int columnCount;
}

class _WeeklyGrid extends StatelessWidget {
  const _WeeklyGrid({required this.slots});

  final List<WeeklySlotRow> slots;

  /// Fim efetivo de um slot: sem hora de término, assume 1 hora.
  static int _endOf(WeeklySlotRow s) => s.endsAtMinutes ?? s.startsAtMinutes + 60;

  /// Distribui os slots de um dia em colunas para que os que se sobrepõem
  /// apareçam lado a lado.
  ///
  /// Agrupa em "clusters" de horários que se tocam e, dentro de cada cluster,
  /// põe cada slot na primeira coluna livre. Todos os slots do mesmo cluster
  /// recebem o mesmo `columnCount`, para terem a mesma largura — senão a grade
  /// ficaria com blocos de larguras diferentes na mesma faixa de horário.
  static List<_LaidOutSlot> _layoutDay(
    List<WeeklySlotRow> daySlots,
    int gridStartMinutes,
  ) {
    if (daySlots.isEmpty) return const [];

    final sorted = [...daySlots]
      ..sort((a, b) => a.startsAtMinutes.compareTo(b.startsAtMinutes));

    final result = <_LaidOutSlot>[];
    var cluster = <WeeklySlotRow>[];
    var clusterEnd = -1;

    void flush() {
      if (cluster.isEmpty) return;
      // Colunas do cluster: cada uma guarda o fim do último slot que recebeu.
      final columnEnds = <int>[];
      final assigned = <WeeklySlotRow, int>{};
      for (final s in cluster) {
        var col = columnEnds.indexWhere((end) => end <= s.startsAtMinutes);
        if (col == -1) {
          columnEnds.add(_endOf(s));
          col = columnEnds.length - 1;
        } else {
          columnEnds[col] = _endOf(s);
        }
        assigned[s] = col;
      }
      for (final s in cluster) {
        final start = s.startsAtMinutes - gridStartMinutes;
        final duration = _endOf(s) - s.startsAtMinutes;
        result.add(_LaidOutSlot(
          slot: s,
          top: start * _kHourHeight / 60,
          // Piso de 22 dp: um slot de poucos minutos viraria um risco
          // intocável.
          height: (duration * _kHourHeight / 60).clamp(22.0, double.infinity),
          column: assigned[s]!,
          columnCount: columnEnds.length,
        ));
      }
      cluster = [];
      clusterEnd = -1;
    }

    for (final s in sorted) {
      if (cluster.isEmpty || s.startsAtMinutes < clusterEnd) {
        cluster.add(s);
        final end = _endOf(s);
        if (end > clusterEnd) clusterEnd = end;
      } else {
        flush();
        cluster.add(s);
        clusterEnd = _endOf(s);
      }
    }
    flush();

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

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
      final end = _endOf(slot);
      if (end > maxMinutes) maxMinutes = end;
    }
    if (minMinutes > maxMinutes) {
      minMinutes = 6 * 60;
      maxMinutes = 22 * 60;
    }
    // Arredonda para a hora cheia mais próxima.
    minMinutes = (minMinutes ~/ 60) * 60;
    maxMinutes = ((maxMinutes + 59) ~/ 60) * 60;

    final hours = <int>[];
    for (int m = minMinutes; m < maxMinutes; m += 60) {
      hours.add(m);
    }
    final bodyHeight = hours.length * _kHourHeight;

    final dayLabels = [
      l.agenda_weekday_mon,
      l.agenda_weekday_tue,
      l.agenda_weekday_wed,
      l.agenda_weekday_thu,
      l.agenda_weekday_fri,
      l.agenda_weekday_sat,
      l.agenda_weekday_sun,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      // A folga no topo existe porque o rótulo da primeira hora é desenhado
      // 7 dp acima da sua linha — sem ela, "06:00" nasce cortado pela borda.
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Régua de horários. Os rótulos ficam **no topo** de cada faixa,
          // alinhados com a linha da hora — é o que permite ler que um bloco
          // começa na metade de uma faixa.
          SizedBox(
            width: _kGutterWidth,
            child: Column(
              children: [
                const SizedBox(height: _kHeaderHeight),
                SizedBox(
                  height: bodyHeight,
                  child: Stack(
                    children: [
                      for (int i = 0; i < hours.length; i++)
                        Positioned(
                          top: i * _kHourHeight - 7,
                          right: 6,
                          child: Text(
                            _formatMinutes(hours[i]),
                            style: AppTypography.caption
                                .copyWith(color: colors.secondaryLabel),
                          ),
                        ),
                    ],
                  ),
                ),
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
              child: SizedBox(
                width: _kDayWidth * 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabeçalho dos dias.
                    SizedBox(
                      height: _kHeaderHeight,
                      child: Row(
                        children: [
                          for (int day = 1; day <= 7; day++)
                            SizedBox(
                              width: _kDayWidth,
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
                    ),
                    // Corpo: linhas de hora ao fundo e os blocos posicionados
                    // por minuto em cima. Era uma célula por hora, o que
                    // arredondava tudo para a hora cheia e escondia
                    // sobreposição — só cabia um slot por célula.
                    SizedBox(
                      height: bodyHeight,
                      child: Stack(
                        children: [
                          for (int i = 0; i <= hours.length; i++)
                            Positioned(
                              top: i * _kHourHeight,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 0.5,
                                color: colors.separator,
                              ),
                            ),
                          for (int day = 1; day <= 7; day++)
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: day * _kDayWidth - 0.5,
                              child: Container(
                                width: 0.5,
                                color: colors.separator,
                              ),
                            ),
                          for (int day = 1; day <= 7; day++)
                            for (final laid in _layoutDay(
                              byDay[day] ?? const [],
                              minMinutes,
                            ))
                              Positioned(
                                top: laid.top,
                                height: laid.height,
                                left: (day - 1) * _kDayWidth +
                                    laid.column *
                                        (_kDayWidth / laid.columnCount),
                                width: _kDayWidth / laid.columnCount,
                                child: _SlotBlock(slot: laid.slot),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloco de um compromisso na grade.
///
/// Posicionado e dimensionado pelo [_WeeklyGrid]: aqui só entram a aparência
/// e o toque. Antes era uma célula fixa de uma hora, que arredondava tudo
/// para a hora cheia; agora a altura vem da duração real.
class _SlotBlock extends ConsumerWidget {
  const _SlotBlock({required this.slot});

  final WeeklySlotRow slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    // A precedência (cor escolhida > derivada da categoria > cor de marca)
    // mora em AppColors.resolve, para grade, lista e editores concordarem —
    // se cada tela decidisse por conta, o mesmo compromisso apareceria de
    // cores diferentes.
    final palette = colors.resolve(
      colorIndex: slot.colorIndex,
      category: slot.category,
    );
    final fill = palette.container;
    final border = palette.accent;
    final onFill = palette.onContainer;

    return GestureDetector(
      onTap: () => _showSlotDetails(context, ref, slot),
      child: Container(
        margin: const EdgeInsets.fromLTRB(1.5, 1, 1.5, 1),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border, width: 1),
        ),
        child: Text(
          slot.title,
          maxLines: 3,
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
///
/// Para admin, a folha também é o caminho para **editar e excluir**. Antes ela
/// só exibia informação: o `WeeklySlotEditorScreen` e o
/// `AgendaRepository.deleteWeeklySlot` existiam, mas nada no app chegava até
/// eles — dava para criar um item do cronograma e nunca mais mexer nele.
void _showSlotDetails(
  BuildContext context,
  WidgetRef ref,
  WeeklySlotRow slot,
) {
  final l = AppLocalizations.of(context);
  final colors = context.colors;
  final isAdmin = ref.read(isAdminProvider);
  final start = _formatMinutes(slot.startsAtMinutes);
  final end = slot.endsAtMinutes != null
      ? _formatMinutes(slot.endsAtMinutes!)
      : null;

  Future<void> delete(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    final confirmed = await ConfirmDialog.show(
      context,
      title: l.action_delete,
      message: l.agenda_slot_delete_confirm,
    );
    if (!confirmed) return;

    try {
      await ref.read(agendaRepositoryProvider).deleteWeeklySlot(slot.id);
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, e.toString(), isError: true);
      }
    }
  }

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
              if (isAdmin) ...[
                const SizedBox(height: 16),
                Container(height: 0.5, color: colors.separator),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        onPressed: () {
                          Navigator.of(context).pop();
                          context.push(
                            '${Routes.slotEditar}?id=${slot.id}',
                          );
                        },
                        child: Text(
                          l.action_edit,
                          style: AppTypography.body
                              .copyWith(color: colors.tint),
                        ),
                      ),
                    ),
                    Expanded(
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        onPressed: () => delete(context),
                        child: Text(
                          l.action_delete,
                          style: AppTypography.body
                              .copyWith(color: colors.destructive),
                        ),
                      ),
                    ),
                  ],
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

class _SlotListTile extends ConsumerWidget {
  const _SlotListTile({required this.slot});

  final WeeklySlotRow slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      // A lista abre a mesma folha da grade: é o único caminho para editar
      // e excluir, e ter dois comportamentos diferentes para o mesmo dado só
      // confundiria.
      onTap: () => _showSlotDetails(context, ref, slot),
    );
  }
}
