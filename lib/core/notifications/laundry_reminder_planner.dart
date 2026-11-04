import 'package:veredas/data/local/app_database.dart';

/// Antecedência do lembrete da lavanderia.
///
/// Trinta minutos dá tempo de separar a roupa e descer até a lavanderia sem
/// virar um aviso que se esquece até a hora. Mudar aqui muda para todo mundo
/// no próximo build; os lembretes já agendados são refeitos na abertura.
const laundryReminderLead = Duration(minutes: 30);

/// Até quantos dias à frente se agenda. O iOS guarda no máximo 64
/// notificações pendentes por app; duas semanas de reservas de uma pessoa
/// ficam muito abaixo disso, e o resto é agendado conforme os dias passam.
const laundryReminderHorizon = Duration(days: 14);

/// Prefixo do `payload` das notificações de lembrete. É por ele que o
/// agendador reconhece os lembretes que são dele entre os pendentes, sem
/// mexer em outras notificações locais.
const laundryPayloadPrefix = 'laundry:';

/// Um lembrete a agendar.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.reservationId,
    required this.fireAt,
    required this.startsAt,
    required this.machineName,
  });

  /// Id da notificação no sistema — derivado do id da reserva.
  final int id;
  final String reservationId;

  /// Hora local em que a notificação aparece.
  final DateTime fireAt;

  /// Hora local em que a reserva começa (vai no texto).
  final DateTime startsAt;
  final String machineName;

  String get payload => '$laundryPayloadPrefix$reservationId';

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.fireAt == fireAt &&
      other.machineName == machineName;

  @override
  int get hashCode => Object.hash(id, fireAt, machineName);
}

/// Id de notificação estável a partir de uma chave (o id da reserva, ou a
/// rota de um push mostrado em primeiro plano).
///
/// FNV-1a de 32 bits, reduzido a 31 bits: o Android exige `int` de Java
/// (positivo é mais seguro em todos os plugins). `String.hashCode` não serve
/// porque **não é estável entre execuções** do Dart — o mesmo motivo de
/// `AppColors.accentFor` não usá-lo. Colisão entre as poucas reservas de uma
/// pessoa é desprezível, e o pior caso é um lembrete trocar o outro.
int stableNotificationId(String reservationId) {
  var hash = 0x811c9dc5;
  for (final unit in reservationId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// Os lembretes que devem existir agora, para as reservas de quem está
/// logado.
///
/// [reservations] já vem filtrada pela pessoa. Reserva cujo horário ou
/// máquina não está no cache (apagado pelo admin) não gera lembrete: sem a
/// hora não há quando avisar.
///
/// A hora de início é montada por componente — `DateTime(y, m, d, h, min)` —
/// e não somando `Duration` à meia-noite, para não errar na virada do horário
/// de verão (mesma regra de `eventDayRange`).
List<PlannedReminder> planLaundryReminders({
  required List<LaundryReservationRow> reservations,
  required List<LaundryTimeSlotRow> slots,
  required List<LaundryMachineRow> machines,
  required DateTime now,
  Duration lead = laundryReminderLead,
  Duration horizon = laundryReminderHorizon,
}) {
  final slotById = {for (final s in slots) s.id: s};
  final machineById = {for (final m in machines) m.id: m};
  final limit = now.add(horizon);

  final planned = <PlannedReminder>[];
  for (final r in reservations) {
    final slot = slotById[r.timeSlotId];
    final machine = machineById[r.machineId];
    if (slot == null || machine == null) continue;

    final day = r.onDate.toLocal();
    final startsAt = DateTime(
      day.year,
      day.month,
      day.day,
      slot.startsAtMinutes ~/ 60,
      slot.startsAtMinutes % 60,
    );
    final fireAt = startsAt.subtract(lead);
    // Reserva feita em cima da hora: o lembrete já teria passado, e a pessoa
    // acabou de reservar — não precisa ser lembrada.
    if (!fireAt.isAfter(now) || startsAt.isAfter(limit)) continue;

    planned.add(
      PlannedReminder(
        id: stableNotificationId(r.id),
        reservationId: r.id,
        fireAt: fireAt,
        startsAt: startsAt,
        machineName: machine.name,
      ),
    );
  }
  planned.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return planned;
}
