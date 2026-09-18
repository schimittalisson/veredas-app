import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/providers/infra_providers.dart';

/// Providers da aba Lavanderia.

/// Segunda-feira da semana exibida, à meia-noite local.
///
/// A grade é semanal como a planilha que ela substitui, e a navegação é por
/// semana inteira — não por dia — porque a pergunta de quem abre a tela é
/// "onde ainda tem vaga", e não "o que tem hoje".
class LaundryWeekNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => mondayOf(DateTime.now());

  void next() => state = state.add(const Duration(days: 7));
  void previous() => state = state.subtract(const Duration(days: 7));
  void reset() => state = mondayOf(DateTime.now());

  /// Segunda-feira da semana de [date], à meia-noite local.
  ///
  /// `weekday` é ISO (1 = segunda), então subtrair `weekday - 1` cai sempre na
  /// segunda. A data é reconstruída em vez de receber um `subtract` de horas
  /// para não carregar o horário original — a grade compara por dia.
  static DateTime mondayOf(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }
}

final laundryWeekProvider =
    NotifierProvider<LaundryWeekNotifier, DateTime>(LaundryWeekNotifier.new);

/// Máquinas ativas — as colunas da grade.
final laundryMachinesProvider =
    StreamProvider<List<LaundryMachineRow>>((ref) {
  return ref.watch(laundryDaoProvider).watchMachines();
});

/// Faixas de horário ativas — as linhas da grade.
final laundryTimeSlotsProvider =
    StreamProvider<List<LaundryTimeSlotRow>>((ref) {
  return ref.watch(laundryDaoProvider).watchTimeSlots();
});

/// Intervalos, indexados por `machineId|timeSlotId|weekday`.
///
/// O mapa existe porque a grade consulta uma vez por célula: varrer a lista
/// a cada célula seria O(células × bloqueios), e a chave composta responde em
/// O(1). O valor é o id do bloqueio, que o admin precisa para remover.
final laundryBlocksProvider = StreamProvider<Map<String, String>>((ref) {
  return ref.watch(laundryDaoProvider).watchBlocks().map((rows) => {
        for (final b in rows) blockKey(b.machineId, b.timeSlotId, b.weekday): b.id,
      });
});

String blockKey(String machineId, String timeSlotId, int weekday) =>
    '$machineId|$timeSlotId|$weekday';

/// Reservas da semana exibida, indexadas por `machineId|timeSlotId|data`.
///
/// Mesma razão do mapa de bloqueios: a grade pergunta célula a célula.
final laundryReservationsProvider =
    StreamProvider<Map<String, LaundryReservationRow>>((ref) {
  final monday = ref.watch(laundryWeekProvider);
  final sunday = monday.add(const Duration(days: 6));
  return ref
      .watch(laundryDaoProvider)
      .watchReservationsBetween(monday, sunday)
      .map((rows) => {
            for (final r in rows)
              reservationKey(r.machineId, r.timeSlotId, r.onDate): r,
          });
});

String reservationKey(String machineId, String timeSlotId, DateTime date) =>
    '$machineId|$timeSlotId|${date.year}-${date.month}-${date.day}';

/// Todas as máquinas e faixas, inclusive inativas — telas de administração.
final laundryAllMachinesProvider =
    StreamProvider<List<LaundryMachineRow>>((ref) {
  return ref.watch(laundryDaoProvider).watchAllMachines();
});

final laundryAllTimeSlotsProvider =
    StreamProvider<List<LaundryTimeSlotRow>>((ref) {
  return ref.watch(laundryDaoProvider).watchAllTimeSlots();
});
