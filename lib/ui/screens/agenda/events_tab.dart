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
        TableCalendar<EventRow>(
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
        Container(height: 0.5, color: colors.separator),
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
          return Column(
            children: data
                .map((event) => EventCard(event: event))
                .toList(),
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

/// Cartão de evento na lista do dia.
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      // O `Card` do Material vira um contêiner arredondado sobre o fundo
      // agrupado — a mesma leitura visual, sem elevação (o iOS separa por
      // contraste de superfície, não por sombra).
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Capa 16:9 quando houver URL; placeholder com ícone otherwise.
              if (event.coverImageUrl != null &&
                  event.coverImageUrl!.isNotEmpty)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: event.coverImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: colors.fill,
                      child: Icon(
                        CupertinoIcons.photo,
                        size: 48,
                        color: colors.secondaryLabel,
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: colors.fill,
                      child: Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        size: 48,
                        color: colors.secondaryLabel,
                      ),
                    ),
                  ),
                )
              else
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: colors.fill,
                    child: Icon(
                      _categoryIcon(event.category),
                      size: 48,
                      color: colors.secondaryLabel,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style:
                          AppTypography.headline.copyWith(color: colors.label),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.clock,
                          size: 16,
                          color: colors.secondaryLabel,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeLabel,
                          style: AppTypography.footnote
                              .copyWith(color: colors.secondaryLabel),
                        ),
                      ],
                    ),
                    if (event.location != null &&
                        event.location!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.location,
                            size: 16,
                            color: colors.secondaryLabel,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              event.location!,
                              style: AppTypography.footnote
                                  .copyWith(color: colors.secondaryLabel),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (event.category != null &&
                        event.category!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      // Chip do Material → pílula simples sobre `fill`.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.fill,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          event.category!,
                          style: AppTypography.caption
                              .copyWith(color: colors.secondaryLabel),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String? category) {
    if (category == null) return CupertinoIcons.calendar;
    final c = category.toLowerCase();
    if (c.contains('culto') || c.contains('reuniao')) {
      return CupertinoIcons.person_3;
    }
    if (c.contains('treinamento') || c.contains('curso')) {
      return CupertinoIcons.book;
    }
    if (c.contains('viagem') || c.contains('saida')) {
      return CupertinoIcons.bus;
    }
    return CupertinoIcons.calendar;
  }
}
