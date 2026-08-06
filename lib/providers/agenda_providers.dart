import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Providers da tela Agenda — streams do drift sobre o cache local.

/// Todos os eventos, ordenados por `startsAt`.
final allEventsProvider = StreamProvider<List<EventRow>>((ref) {
  return ref.watch(agendaDaoProvider).watchAllEvents();
});

/// Slots do cronograma semanal, ordenados por dia e horário.
final weeklySlotsProvider = StreamProvider<List<WeeklySlotRow>>((ref) {
  return ref.watch(agendaDaoProvider).watchWeeklySlots();
});

/// Slots ativos agrupados por dia da semana (1=seg ... 7=dom).
///
/// Filtros e agrupamento ficam no provider (não no DAO) porque são
/// específicos da UI — o DAO expõe o stream cru para reuso.
final weeklySlotsByDayProvider =
    Provider<Map<int, List<WeeklySlotRow>>>((ref) {
  final slots = ref.watch(weeklySlotsProvider).value ?? const [];
  final map = <int, List<WeeklySlotRow>>{};
  for (final slot in slots) {
    if (!slot.isActive) continue;
    (map[slot.weekday] ??= []).add(slot);
  }
  return map;
});

/// Eventos de um dia específico (apenas a data, ignorando horário).
///
/// `family` porque a UI precisa de eventos por dia selecionado no calendário.
final eventsForDayProvider =
    FutureProvider.family<List<EventRow>, DateTime>((ref, day) async {
  final events = ref.watch(allEventsProvider).value ?? const [];
  return events.where((e) {
    final start = e.startsAt;
    return start.year == day.year &&
        start.month == day.month &&
        start.day == day.day;
  }).toList();
});

/// Conjunto de dias que têm pelo menos um evento (para o `eventLoader`
/// do `TableCalendar` marcar os dias).
final daysWithEventsProvider = Provider<Set<DateTime>>((ref) {
  final events = ref.watch(allEventsProvider).value ?? const [];
  return events.map((e) {
    final s = e.startsAt;
    return DateTime(s.year, s.month, s.day);
  }).toSet();
});

/// Cor que cada categoria já usa, para o editor sugerir sozinho.
///
/// Sem isso, criar um segundo "oracao" exigiria lembrar de escolher roxo de
/// novo — e esquecer uma vez já quebra a leitura da grade. A chave é a
/// categoria em minúsculas, para "Oracao" e "oracao" não divergirem.
///
/// Quando a mesma categoria aparece com cores diferentes (o usuário mudou de
/// ideia num registro), vence a **mais frequente**: é a que representa o que
/// ele quis dizer no conjunto.
final categoryColorsProvider = Provider<Map<String, int>>((ref) {
  final slots = ref.watch(weeklySlotsProvider).value ?? const [];
  final events = ref.watch(allEventsProvider).value ?? const [];

  final counts = <String, Map<int, int>>{};
  void tally(String? category, int? colorIndex) {
    if (category == null || colorIndex == null) return;
    final key = category.trim().toLowerCase();
    if (key.isEmpty) return;
    final byColor = counts[key] ??= {};
    byColor[colorIndex] = (byColor[colorIndex] ?? 0) + 1;
  }

  for (final s in slots) {
    tally(s.category, s.colorIndex);
  }
  for (final e in events) {
    tally(e.category, e.colorIndex);
  }

  return {
    for (final entry in counts.entries)
      entry.key:
          entry.value.entries.reduce((a, b) => b.value > a.value ? b : a).key,
  };
});
