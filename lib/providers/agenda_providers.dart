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

/// Categorias já em uso, em ordem alfabética.
///
/// É a paleta oferecida nos editores. A cor de um registro **deriva da
/// categoria** (`AppColors.accentFor`), então escolher a categoria é escolher
/// a cor — e listar só as que já existem mantém a leitura da grade estável:
/// "roxo é intercessão" continua valendo em todo lugar.
///
/// Junta cronograma e eventos de propósito: são a mesma linguagem visual para
/// o obreiro, e separar as duas listas faria a mesma categoria receber cores
/// diferentes em cada tela.
final usedCategoriesProvider = Provider<List<String>>((ref) {
  final slots = ref.watch(weeklySlotsProvider).value ?? const [];
  final events = ref.watch(allEventsProvider).value ?? const [];

  final categories = <String>{
    for (final s in slots)
      if (s.category != null && s.category!.trim().isNotEmpty)
        s.category!.trim(),
    for (final e in events)
      if (e.category != null && e.category!.trim().isNotEmpty)
        e.category!.trim(),
  }.toList()
    ..sort();

  return categories;
});
