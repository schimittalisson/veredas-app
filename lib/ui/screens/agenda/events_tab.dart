import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/agenda_providers.dart';
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
          calendarStyle: CalendarStyle(
            // Herda do ColorScheme — não hardcodar cores.
            markerDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const Divider(height: 1),
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
          icon: Icons.event_busy,
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
              icon: Icons.event_outlined,
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
        icon: Icons.event_outlined,
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
              style: Theme.of(context).textTheme.titleMedium,
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
    final theme = Theme.of(context);

    String timeLabel;
    if (event.allDay) {
      timeLabel = l.agenda_all_day;
    } else if (event.endsAt != null) {
      timeLabel =
          '${DateFormat.Hm().format(event.startsAt)} – ${DateFormat.Hm().format(event.endsAt!)}';
    } else {
      timeLabel = DateFormat.Hm().format(event.startsAt);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // TODO: navegar para /evento/:id
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Capa 16:9 quando houver URL; placeholder com ícone otherwise.
            if (event.coverImageUrl != null && event.coverImageUrl!.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  // TODO: cached_network_image quando houver URL real.
                  // Por ora, placeholder.
                  child: Icon(
                    Icons.image_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    _categoryIcon(event.category),
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(timeLabel, style: theme.textTheme.bodySmall),
                    ],
                  ),
                  if (event.location != null &&
                      event.location!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location!,
                            style: theme.textTheme.bodySmall,
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
                    Chip(
                      label: Text(event.category!),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(String? category) {
    if (category == null) return Icons.event_outlined;
    final c = category.toLowerCase();
    if (c.contains('culto') || c.contains('reuniao')) {
      return Icons.groups_outlined;
    }
    if (c.contains('treinamento') || c.contains('curso')) {
      return Icons.school_outlined;
    }
    if (c.contains('viagem') || c.contains('saida')) {
      return Icons.directions_bus_outlined;
    }
    return Icons.event_outlined;
  }
}
