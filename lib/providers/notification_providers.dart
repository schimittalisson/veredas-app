import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/config/env.dart';
import 'package:veredas/core/notifications/laundry_reminder_planner.dart';
import 'package:veredas/data/local/app_database.dart';
import 'package:veredas/data/remote/local_notifications.dart';
import 'package:veredas/data/remote/push_messaging.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/infra_providers.dart';
import 'package:veredas/providers/laundry_providers.dart';

/// Notificações locais (lembrete da lavanderia, push em primeiro plano no
/// Android). Ponto de override nos testes.
final localNotificationsProvider = Provider<LocalNotifications>(
  (ref) => PluginLocalNotifications(),
);

/// Push remoto. Sem Supabase não há onde registrar o token, então nem tenta.
final pushMessagingProvider = Provider<PushMessaging>((ref) {
  if (!Env.isConfigured) return const NoopPushMessaging();
  return FirebasePushMessaging(ref.watch(supabaseClientProvider));
});

/// Relógio dos lembretes. Provider para os testes fixarem a hora.
final reminderClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Reservas de hoje em diante de quem está logado.
final myUpcomingReservationsProvider =
    StreamProvider<List<LaundryReservationRow>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);
  final now = ref.read(reminderClockProvider)();
  final today = DateTime(now.year, now.month, now.day);
  return ref
      .watch(laundryDaoProvider)
      .watchUpcomingReservationsOf(userId, today);
});

/// Os lembretes que devem estar agendados agora. Vazio sem login — e é isso
/// que faz o logout cancelar os lembretes de quem saiu.
///
/// **Nulo enquanto alguma stream carrega**, e não vazio: o agendador cancela
/// o que não está no plano, e um plano vazio na abertura do app apagaria os
/// lembretes de todo mundo até as streams responderem.
///
/// Usa as listas **com** inativos: uma máquina desativada depois da reserva
/// continua sendo onde a pessoa vai lavar a roupa.
final plannedLaundryRemindersProvider = Provider<List<PlannedReminder>?>((ref) {
  final reservations = ref.watch(myUpcomingReservationsProvider).value;
  final slots = ref.watch(laundryAllTimeSlotsProvider).value;
  final machines = ref.watch(laundryAllMachinesProvider).value;
  if (reservations == null || slots == null || machines == null) {
    return null;
  }
  return planLaundryReminders(
    reservations: reservations,
    slots: slots,
    machines: machines,
    now: ref.read(reminderClockProvider)(),
  );
});
