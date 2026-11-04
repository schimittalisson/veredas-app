import 'package:flutter/foundation.dart';

import 'package:veredas/core/notifications/laundry_reminder_planner.dart';
import 'package:veredas/data/remote/local_notifications.dart';

/// Faz os lembretes agendados no sistema baterem com o plano.
///
/// **Reconciliação, não eventos.** Em vez de agendar ao reservar e cancelar
/// ao desmarcar, o plano inteiro é recalculado do cache a cada mudança e
/// aplicado aqui. Assim valem também a reserva feita em outro aparelho, a
/// desmarcada pelo admin, o horário que o admin mudou e o logout — tudo chega
/// pelo mesmo caminho, o stream do drift.
///
/// Os lembretes são reconhecidos pelo `payload` com [laundryPayloadPrefix]:
/// qualquer outra notificação local pendente não é tocada.
class LaundryReminderScheduler {
  LaundryReminderScheduler(this._notifications);

  final LocalNotifications _notifications;

  /// As aplicações rodam em fila. Duas emissões seguidas do stream, rodando
  /// em paralelo, poderiam cancelar o que a outra acabou de agendar.
  Future<void> _queue = Future.value();

  Future<void> apply(
    List<PlannedReminder> plan, {
    required String Function(PlannedReminder) title,
    required String Function(PlannedReminder) body,
  }) {
    _queue = _queue.then((_) async {
      try {
        await _apply(plan, title: title, body: body);
      } catch (e) {
        // Um lembrete que não foi agendado não pode derrubar o app; a
        // próxima mudança no cache tenta de novo.
        debugPrint('Lembretes da lavanderia: ${e.runtimeType}');
      }
    });
    return _queue;
  }

  Future<void> _apply(
    List<PlannedReminder> plan, {
    required String Function(PlannedReminder) title,
    required String Function(PlannedReminder) body,
  }) async {
    final wanted = {for (final p in plan) p.id};
    final pending = await _notifications.pending();

    for (final entry in pending.entries) {
      final isOurs = entry.value?.startsWith(laundryPayloadPrefix) ?? false;
      if (isOurs && !wanted.contains(entry.key)) {
        await _notifications.cancel(entry.key);
      }
    }

    // Agenda de novo mesmo o que já estava pendente: o mesmo id substitui o
    // anterior nos dois sistemas, e é assim que uma mudança de horário feita
    // pelo admin chega ao lembrete. São poucas por pessoa.
    for (final p in plan) {
      await _notifications.schedule(
        id: p.id,
        at: p.fireAt,
        title: title(p),
        body: body(p),
        payload: p.payload,
      );
    }
  }
}
