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


// ---------------------------------------------------------------------------
// Em quais dias um evento acontece
// ---------------------------------------------------------------------------

/// Meia-noite local do dia de [dt].
DateTime _dayOf(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Primeiro e último dia (meia-noite local) em que [e] acontece.
///
/// Um evento sem `endsAt` ocupa só o dia do `startsAt`. Com `endsAt`, ocupa
/// **todos** os dias do intervalo: é o que faz um retiro de sexta a domingo
/// aparecer nos três dias do calendário, e não só na sexta. Antes disto a
/// bolinha e a lista do dia liam apenas `startsAt`, então o evento
/// simplesmente não existia nos dias do meio e no último.
///
/// Dois detalhes que não são óbvios:
///
/// 1. **Fim exatamente à meia-noite não conta o dia seguinte — exceto no dia
///    inteiro.** Um evento de 20:00 às 00:00 termina no instante em que o
///    outro dia começa; marcá-lo ali poria uma bolinha num dia em que nada
///    acontece, e a roda de seleção deixa escolher 00:00. Já no **dia
///    inteiro** a meia-noite é justamente como o editor grava a data de fim
///    (`_pickDateTime` não pede hora), e ali ela significa "este dia todo" —
///    descontar um dia encurtaria um retiro de 21 a 23 para 21 a 22.
/// 2. **A aritmética é por componente (`DateTime(y, m, d - 1)`), não por
///    `Duration`.** Somar ou subtrair 24 h de uma meia-noite erra o dia na
///    virada do horário de verão. O Brasil não tem mais DST, mas o app lê
///    datas do servidor e não custa nada estar certo.
({DateTime first, DateTime last}) eventDayRange(EventRow e) {
  final first = _dayOf(e.startsAt);
  final end = e.endsAt;
  if (end == null || !end.isAfter(e.startsAt)) return (first: first, last: first);

  var last = _dayOf(end);
  if (!e.allDay && end == last && last.isAfter(first)) {
    last = DateTime(last.year, last.month, last.day - 1);
  }
  if (last.isBefore(first)) last = first;

  // Teto de um ano. Um intervalo maior é quase certamente erro de digitação na
  // data, e pontilhar o calendário por anos o deixa inútil — a informação
  // "tem algo todo dia" não é informação.
  final cap = DateTime(first.year + 1, first.month, first.day);
  if (last.isAfter(cap)) last = cap;

  return (first: first, last: last);
}

/// `true` se [e] acontece em [day] (compara só a data).
bool eventOccursOn(EventRow e, DateTime day) {
  final d = _dayOf(day);
  final range = eventDayRange(e);
  return !d.isBefore(range.first) && !d.isAfter(range.last);
}

/// Eventos de um dia específico (apenas a data, ignorando horário).
///
/// Inclui os eventos de vários dias que **atravessam** este dia, não só os que
/// começam nele — ver [eventDayRange].
///
/// `family` porque a UI precisa de eventos por dia selecionado no calendário.
final eventsForDayProvider =
    FutureProvider.family<List<EventRow>, DateTime>((ref, day) async {
  final events = ref.watch(allEventsProvider).value ?? const [];
  return events.where((e) => eventOccursOn(e, day)).toList();
});

/// Conjunto de dias que têm pelo menos um evento (para o `eventLoader`
/// do `TableCalendar` marcar os dias).
///
/// Um evento de vários dias entra com **todos** os seus dias.
final daysWithEventsProvider = Provider<Set<DateTime>>((ref) {
  final events = ref.watch(allEventsProvider).value ?? const [];
  final days = <DateTime>{};
  for (final e in events) {
    final range = eventDayRange(e);
    for (var d = range.first;
        !d.isAfter(range.last);
        d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(d);
    }
  }
  return days;
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
