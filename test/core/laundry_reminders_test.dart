import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:veredas/core/notifications/laundry_reminder_planner.dart';
import 'package:veredas/core/notifications/laundry_reminder_scheduler.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/remote/local_notifications.dart';

// Lembrete da reserva da lavanderia: o plano sai do cache, e o agendador o
// aplica no sistema.

LaundryReservationRow _res(String id, DateTime day, {String slot = 's14'}) =>
    LaundryReservationRow(
      id: id,
      machineId: 'm1',
      timeSlotId: slot,
      onDate: DateTime(day.year, day.month, day.day),
      userId: 'u-me',
      userName: 'Eu',
      updatedAt: DateTime.utc(2026, 11, 1),
    );

final _slots = [
  LaundryTimeSlotRow(
    id: 's14',
    startsAtMinutes: 14 * 60,
    endsAtMinutes: 16 * 60,
    isActive: true,
    ordering: 0,
    updatedAt: DateTime.utc(2026, 11, 1),
  ),
  LaundryTimeSlotRow(
    id: 's0730',
    startsAtMinutes: 7 * 60 + 30,
    isActive: false, // desativada depois da reserva: o lembrete continua
    ordering: 1,
    updatedAt: DateTime.utc(2026, 11, 1),
  ),
];

final _machines = [
  LaundryMachineRow(
    id: 'm1',
    name: 'Máquina grande',
    isActive: true,
    ordering: 0,
    updatedAt: DateTime.utc(2026, 11, 1),
  ),
];

List<PlannedReminder> _plan(
  List<LaundryReservationRow> reservations,
  DateTime now,
) =>
    planLaundryReminders(
      reservations: reservations,
      slots: _slots,
      machines: _machines,
      now: now,
    );

class _FakeNotifications implements LocalNotifications {
  final scheduled = <int, ({DateTime at, String payload, String body})>{};
  final cancelled = <int>[];

  /// Notificação que não é lembrete — não pode ser tocada.
  final others = <int, String?>{999: 'route:/aviso?id=a1'};

  @override
  Future<Map<int, String?>> pending() async => {
        ...others,
        for (final e in scheduled.entries) e.key: e.value.payload,
      };

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
  }) async {
    scheduled[id] = (at: at, payload: payload, body: body);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
    others.remove(id);
  }

  @override
  Future<void> init({
    required String announcementsChannelName,
    required String laundryChannelName,
  }) async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> showAnnouncement({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {}
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Future<String?> launchPayload() async => null;
}

void main() {
  final now = DateTime(2026, 11, 4, 10);

  group('plano', () {
    test('avisa 30 minutos antes do horário reservado', () {
      final plan = _plan([_res('r1', DateTime(2026, 11, 5))], now);

      expect(plan, hasLength(1));
      expect(plan.single.startsAt, DateTime(2026, 11, 5, 14));
      expect(plan.single.fireAt, DateTime(2026, 11, 5, 13, 30));
      expect(plan.single.machineName, 'Máquina grande');
      expect(plan.single.payload, 'laundry:r1');
    });

    test('reserva de hoje mais tarde entra; a que já passou, não', () {
      final plan = _plan([
        _res('tarde', DateTime(2026, 11, 4)), // 14:00 hoje
        _res('cedo', DateTime(2026, 11, 4), slot: 's0730'), // 07:30 hoje
      ], now);

      expect(plan.map((p) => p.reservationId), ['tarde']);
    });

    test('reserva em cima da hora não gera lembrete atrasado', () {
      // 13:45 e a reserva é às 14:00: o lembrete das 13:30 já passou.
      final plan =
          _plan([_res('r1', DateTime(2026, 11, 4))], DateTime(2026, 11, 4, 13, 45));
      expect(plan, isEmpty);
    });

    test('horário inativo continua valendo; horário apagado não', () {
      final plan = _plan([
        _res('inativo', DateTime(2026, 11, 6), slot: 's0730'),
        _res('apagado', DateTime(2026, 11, 6), slot: 'nao-existe'),
      ], now);

      expect(plan.map((p) => p.reservationId), ['inativo']);
    });

    test('só até duas semanas à frente, em ordem de disparo', () {
      final plan = _plan([
        _res('longe', DateTime(2026, 11, 30)),
        _res('depois', DateTime(2026, 11, 10)),
        _res('antes', DateTime(2026, 11, 6)),
      ], now);

      expect(plan.map((p) => p.reservationId), ['antes', 'depois']);
    });

    test('o id da notificação é estável e positivo', () {
      expect(stableNotificationId('r1'), stableNotificationId('r1'));
      expect(stableNotificationId('r1'), isNot(stableNotificationId('r2')));
      expect(stableNotificationId('qualquer-uuid-longo'), greaterThan(0));
      // Valor fixo: se mudar, todo lembrete já agendado vira órfão.
      // FNV-1a de "r1", conferido fora do Dart.
      expect(stableNotificationId('r1'), 206831020);
    });
  });

  group('agendador', () {
    String title(PlannedReminder _) => 'Lavanderia em 30 minutos';
    String body(PlannedReminder p) => 'Sua reserva na ${p.machineName}';

    test('agenda o plano e cancela o lembrete que saiu dele', () async {
      final fake = _FakeNotifications();
      final scheduler = LaundryReminderScheduler(fake);

      await scheduler.apply(
        _plan([
          _res('r1', DateTime(2026, 11, 5)),
          _res('r2', DateTime(2026, 11, 6)),
        ], now),
        title: title,
        body: body,
      );
      expect(fake.scheduled.keys.toSet(), {
        stableNotificationId('r1'),
        stableNotificationId('r2'),
      });

      // r2 desmarcada (aqui, em outro aparelho ou pelo admin).
      await scheduler.apply(
        _plan([_res('r1', DateTime(2026, 11, 5))], now),
        title: title,
        body: body,
      );

      expect(fake.scheduled.keys, [stableNotificationId('r1')]);
      expect(fake.cancelled, [stableNotificationId('r2')]);
    });

    test('plano vazio (logout) cancela só os lembretes', () async {
      final fake = _FakeNotifications();
      final scheduler = LaundryReminderScheduler(fake);
      await scheduler.apply(
        _plan([_res('r1', DateTime(2026, 11, 5))], now),
        title: title,
        body: body,
      );

      await scheduler.apply(const [], title: title, body: body);

      expect(fake.scheduled, isEmpty);
      // A notificação que não é da lavanderia ficou.
      expect(fake.others.keys, [999]);
    });

    test('horário mudado pelo admin reagenda com a hora nova', () async {
      final fake = _FakeNotifications();
      final scheduler = LaundryReminderScheduler(fake);
      final r = _res('r1', DateTime(2026, 11, 5));
      await scheduler.apply(_plan([r], now), title: title, body: body);

      final moved = planLaundryReminders(
        reservations: [r],
        slots: [
          _slots.first.copyWith(startsAtMinutes: 16 * 60),
        ],
        machines: _machines,
        now: now,
      );
      await scheduler.apply(moved, title: title, body: body);

      expect(
        fake.scheduled[stableNotificationId('r1')]!.at,
        DateTime(2026, 11, 5, 15, 30),
      );
    });

    test('aplicações seguidas rodam em fila', () async {
      final fake = _FakeNotifications();
      final scheduler = LaundryReminderScheduler(fake);

      // Sem a fila, a segunda leria os pendentes antes de a primeira agendar,
      // e r1 ficaria agendado depois de ter saído do plano.
      unawaited(
        scheduler.apply(
          _plan([_res('r1', DateTime(2026, 11, 5))], now),
          title: title,
          body: body,
        ),
      );
      await scheduler.apply(
        _plan([_res('r2', DateTime(2026, 11, 6))], now),
        title: title,
        body: body,
      );

      expect(fake.scheduled.keys, [stableNotificationId('r2')]);
    });
  });
}
