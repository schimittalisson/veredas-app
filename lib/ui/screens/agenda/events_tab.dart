import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
// `table_calendar` é construído sobre o Material (usa `InkWell` e `Table` do
// Material internamente) e não tem equivalente Cupertino no pub. Mantê-lo é
// deliberado: reescrever um calendário de mês à mão custaria muito mais do que
// o ganho estético. Ele funciona porque `MaterialCompat` fornece o ancestral
// `Material` globalmente; aqui só ajustamos `CalendarStyle`/`HeaderStyle` com
// as cores de `context.colors` para ele não destoar do resto da tela.
//
// Nada de `material.dart` é importado neste arquivo — os tipos de estilo do
// pacote (`CalendarStyle`, `HeaderStyle`, `DaysOfWeekStyle`) vivem em
// `flutter/widgets.dart`, que o `cupertino.dart` já reexporta.
import 'package:table_calendar/table_calendar.dart';

import 'package:veredas/core/theme/app_theme.dart';
import 'package:veredas/core/theme/material_compat.dart';
import 'package:veredas/core/theme/app_typography.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/agenda_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';
import 'package:veredas/ui/widgets/empty_state.dart';
import 'package:veredas/ui/widgets/loading_state.dart';

/// Aba Eventos da Agenda.
///
/// `TableCalendar` no formato `month` (recolhível para `week`) + lista do dia
/// selecionado. Se o dia é hoje e não há eventos, mostra "Próximos eventos".
class EventsTab extends ConsumerStatefulWidget {
  const EventsTab({super.key});

  @override
  ConsumerState<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends ConsumerState<EventsTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _selectedDay = _normalize(DateTime.now());
  }

  /// Normaliza para meia-noite (sem horário), para comparação de dias.
  DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final daysWithEvents = ref.watch(daysWithEventsProvider);
    final colors = context.colors;

    return ListView(
      children: [
        // O calendário mora num cartão arredondado, e não solto sobre o fundo:
        // ele é uma unidade de conteúdo fechada, e o contorno é o que separa a
        // grade de dias da lista de eventos logo abaixo.
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          // O TableCalendar usa InkWell internamente e exige um ancestral
          // Material, que não existe sob CupertinoApp. A ilha de Material
          // fica restrita a ele — ver material_compat.dart.
          child: MaterialCompat(
            colors: colors,
            brightness: CupertinoTheme.brightnessOf(context),
            child: TableCalendar<EventRow>(
              firstDay: DateTime.utc(2020),
              lastDay: DateTime.utc(2030),
              focusedDay: _focusedDay,
              locale: 'pt_BR',
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selected, focused) {
                setState(() {
                  _selectedDay = selected;
                  _focusedDay = focused;
                });
              },
              calendarFormat: _calendarFormat,
              onFormatChanged: (format) {
                setState(() => _calendarFormat = format);
              },
              // TODO l10n: agenda_calendar_format_month / agenda_calendar_format_week
              availableCalendarFormats: const {
                CalendarFormat.month: 'Mês',
                CalendarFormat.week: 'Semana',
              },
              eventLoader: (day) {
                final normalized = _normalize(day);
                // O eventLoader recebe um DateTime; filtramos os eventos cujo
                // startsAt cai neste dia. O daysWithEventsProvider já tem o
                // conjunto de dias; aqui usamos o allEventsProvider para obter
                // os eventos completos.
                if (!daysWithEvents.contains(normalized)) return const [];
                final events = ref.read(allEventsProvider).value ?? const [];
                return events.where((e) {
                  final s = e.startsAt;
                  return s.year == day.year &&
                      s.month == day.month &&
                      s.day == day.day;
                }).toList();
              },
              headerStyle: HeaderStyle(
                titleCentered: true,
                titleTextStyle: AppTypography.headline.copyWith(color: colors.label),
                formatButtonTextStyle:
                    AppTypography.footnoteEmphasis.copyWith(color: colors.tint),
                formatButtonDecoration: BoxDecoration(
                  color: colors.fill,
                  borderRadius: BorderRadius.circular(8),
                ),
                formatButtonPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                // Chevrons do iOS no lugar das setas do Material.
                leftChevronIcon: Icon(CupertinoIcons.chevron_left,
                    size: 20, color: colors.tint),
                rightChevronIcon: Icon(CupertinoIcons.chevron_right,
                    size: 20, color: colors.tint),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle:
                    AppTypography.caption.copyWith(color: colors.secondaryLabel),
                weekendStyle:
                    AppTypography.caption.copyWith(color: colors.tertiaryLabel),
              ),
              calendarStyle: CalendarStyle(
                // Toda cor sai de context.colors — nada hardcodado, e o tema
                // escuro passa a valer também dentro do calendário.
                defaultTextStyle:
                    AppTypography.subheadline.copyWith(color: colors.label),
                weekendTextStyle:
                    AppTypography.subheadline.copyWith(color: colors.secondaryLabel),
                outsideTextStyle:
                    AppTypography.subheadline.copyWith(color: colors.tertiaryLabel),
                disabledTextStyle:
                    AppTypography.subheadline.copyWith(color: colors.tertiaryLabel),
                todayTextStyle:
                    AppTypography.subheadlineEmphasis.copyWith(color: colors.tint),
                todayDecoration: BoxDecoration(
                  color: colors.tintContainer,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle:
                    AppTypography.subheadlineEmphasis.copyWith(color: colors.onTint),
                selectedDecoration: BoxDecoration(
                  color: colors.tint,
                  shape: BoxShape.circle,
                ),
                markerDecoration: BoxDecoration(
                  color: colors.tint,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        // Sem separador aqui: ele existia quando o calendário ia de borda a
        // borda. Agora o próprio contorno do cartão faz a separação, e a linha
        // só cortava a tela logo abaixo dele.
        _SelectedDayEvents(selectedDay: _selectedDay!),
      ],
    );
  }
}

class _SelectedDayEvents extends ConsumerWidget {
  const _SelectedDayEvents({required this.selectedDay});

  final DateTime selectedDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final events = ref.watch(eventsForDayProvider(selectedDay));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: events.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: LoadingState(),
        ),
        error: (_,_) => EmptyState(
          title: l.agenda_no_events_day,
          icon: CupertinoIcons.calendar_badge_minus,
          compact: true,
        ),
        data: (data) {
          if (data.isEmpty) {
            // Se é hoje e não há eventos, mostra próximos.
            final now = DateTime.now();
            final isToday = selectedDay.year == now.year &&
                selectedDay.month == now.month &&
                selectedDay.day == now.day;
            if (isToday) {
              return _UpcomingEvents();
            }
            return EmptyState(
              title: l.agenda_no_events_day,
              icon: CupertinoIcons.calendar,
              compact: true,
            );
          }
          // Cabeçalho com o dia por extenso: sem ele, a lista fica órfã do
          // calendário e não se sabe a que data os eventos pertencem depois
          // de rolar a tela.
          final dayLabel = DateFormat("EEEE d", 'pt_BR').format(selectedDay);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  l.agenda_day_events_section(
                    dayLabel[0].toUpperCase() + dayLabel.substring(1),
                  ),
                  style: AppTypography.headline
                      .copyWith(color: context.colors.label),
                ),
              ),
              ...data.map((event) => EventCard(event: event)),
            ],
          );
        },
      ),
    );
  }
}

class _UpcomingEvents extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final events = ref.watch(allEventsProvider).value ?? const [];
    final now = DateTime.now();
    final upcoming = events
        .where((e) => e.startsAt.isAfter(now))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    if (upcoming.isEmpty) {
      return EmptyState(
        title: l.agenda_no_events_upcoming,
        icon: CupertinoIcons.calendar,
        compact: true,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l.agenda_upcoming_section,
              style: AppTypography.headline
                  .copyWith(color: context.colors.label),
            ),
          ),
        ),
        ...upcoming.take(5).map((event) => EventCard(event: event)),
      ],
    );
  }
}

/// Linha de evento na lista do dia.
///
/// **Compacta de propósito.** A versão anterior abria com uma capa 16:9 — e,
/// quando o evento não tinha imagem, com um retângulo cinza e um ícone
/// gigante. Três eventos já ocupavam a tela inteira, e o espaço era gasto com
/// um placeholder que não informa nada.
///
/// Agora cada evento é uma linha de ~64 dp: barra colorida da categoria,
/// título, horário, e a categoria como pílula à direita. A capa, quando
/// existe, vira uma miniatura — a informação não se perde, só deixa de mandar
/// no layout. A imagem em tamanho cheio é assunto da tela de detalhe.
class EventCard extends StatelessWidget {
  const EventCard({required this.event, super.key});

  final EventRow event;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = context.colors;

    String timeLabel;
    if (event.allDay) {
      timeLabel = l.agenda_all_day;
    } else if (event.endsAt != null) {
      timeLabel =
          '${DateFormat.Hm().format(event.startsAt)} – ${DateFormat.Hm().format(event.endsAt!)}';
    } else {
      timeLabel = DateFormat.Hm().format(event.startsAt);
    }

    // Mesma precedência da grade do cronograma: cor escolhida, senão
    // derivada da categoria. Ver AppColors.resolve.
    final category = event.category ?? '';
    final palette = colors.resolve(
      colorIndex: event.colorIndex,
      category: event.category,
    );
    final accent = palette.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: () {
          // TODO: tela de detalhe do evento (/evento/:id) com mapa e anexos.
          // Por ora, abre o editor em modo edição.
          context.push('${Routes.eventoEditar}?id=${event.id}');
        },
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Barra da categoria: ocupa a altura toda da linha, que é o
                // que o IntrinsicHeight garante.
                Container(width: 4, color: accent),
                if (event.coverImageUrl != null &&
                    event.coverImageUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: event.coverImageUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            ColoredBox(color: colors.fill),
                        errorWidget: (context, url, error) => ColoredBox(
                          color: colors.fill,
                          child: Icon(
                            CupertinoIcons.photo,
                            size: 18,
                            color: colors.tertiaryLabel,
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          event.title,
                          style: AppTypography.subheadlineEmphasis
                              .copyWith(color: colors.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.clock,
                              size: 13,
                              color: colors.secondaryLabel,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              timeLabel,
                              style: AppTypography.caption
                                  .copyWith(color: colors.secondaryLabel),
                            ),
                            // O local entra na mesma linha do horário: numa
                            // linha compacta ele não merece uma terceira.
                            if (event.location != null &&
                                event.location!.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Icon(
                                CupertinoIcons.location,
                                size: 13,
                                color: colors.secondaryLabel,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  event.location!,
                                  style: AppTypography.caption
                                      .copyWith(color: colors.secondaryLabel),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (category.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: palette.container,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        category,
                        style: AppTypography.caption.copyWith(
                          color: palette.onContainer,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
