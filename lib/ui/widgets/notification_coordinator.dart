import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veredas/core/notifications/laundry_reminder_planner.dart';
import 'package:veredas/core/notifications/laundry_reminder_scheduler.dart';
import 'package:veredas/data/remote/local_notifications.dart';
import 'package:veredas/data/remote/push_messaging.dart';
import 'package:veredas/l10n/app_localizations.dart';
import 'package:veredas/providers/auth_providers.dart';
import 'package:veredas/providers/notification_providers.dart';
import 'package:veredas/providers/sync_providers.dart';
import 'package:veredas/ui/navigation/app_router.dart';

/// Liga as notificações ao resto do app.
///
/// - **Lembrete da lavanderia**: observa o plano
///   (`plannedLaundryRemindersProvider`) e o aplica no sistema.
/// - **Push de aviso novo**: registra o token do aparelho no login, mostra o
///   push que chega com o app aberto (Android) e sincroniza para o aviso já
///   estar no cache quando a pessoa tocar.
/// - **Toque na notificação**: abre o aviso, ou a aba Escalas no caso da
///   lavanderia.
///
/// Fica acima do router, no `builder` do `CupertinoApp`, pelo mesmo motivo do
/// `SyncCoordinator`: o Riverpod 3 pausa providers fora de tela, e um
/// listener preso a uma aba pararia ao trocar de aba.
///
/// O pedido de permissão é feito **depois do login**, não na abertura: antes
/// do login a pessoa nem sabe ainda o que o app vai avisar. É um pedido só,
/// do sistema, que vale para o lembrete e para o push.
class NotificationCoordinator extends ConsumerStatefulWidget {
  const NotificationCoordinator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NotificationCoordinator> createState() =>
      _NotificationCoordinatorState();
}

class _NotificationCoordinatorState
    extends ConsumerState<NotificationCoordinator> {
  late final LocalNotifications _local = ref.read(localNotificationsProvider);
  late final PushMessaging _push = ref.read(pushMessagingProvider);
  late final LaundryReminderScheduler _scheduler =
      LaundryReminderScheduler(_local);

  final _subs = <StreamSubscription<Object?>>[];
  bool _localReady = false;
  bool _pushReady = false;

  /// Usuário cujo FID já foi registrado nesta execução.
  String? _registeredFor;

  /// Rota vinda de uma notificação tocada antes de haver sessão aprovada
  /// (app aberto pelo toque, ainda no splash). Abre assim que der.
  String? _pendingRoute;

  @override
  void initState() {
    super.initState();
    // Post-frame: o init lê o l10n (nome dos canais), que precisa do
    // contexto montado.
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _init() async {
    if (!mounted) return;
    final l = AppLocalizations.of(context);

    try {
      await _local.init(
        announcementsChannelName: l.notification_channel_announcements,
        laundryChannelName: l.notification_channel_laundry,
      );
      _localReady = true;
    } catch (e) {
      debugPrint('Notificações locais indisponíveis (${e.runtimeType}).');
    }
    if (!mounted) return;

    if (_localReady) {
      _subs.add(_local.taps.listen(_openPayload));
      final launch = await _local.launchPayload();
      if (launch != null) _openPayload(launch);
      _applyReminders(ref.read(plannedLaundryRemindersProvider));
    }

    _pushReady = await _push.init();
    if (!mounted || !_pushReady) return;

    _subs
      ..add(_push.foregroundMessages.listen(_onForegroundPush))
      ..add(_push.openedMessages.listen((e) => _openRoute(e.route)))
      ..add(_push.registrations.listen(_registerToken));
    final initial = await _push.initialMessage();
    if (initial != null) _openRoute(initial.route);

    unawaited(_onSessionMaybeReady());
  }

  // --- Lembrete da lavanderia ------------------------------------------------

  void _applyReminders(List<PlannedReminder>? plan) {
    if (!_localReady || plan == null || !mounted) return;
    final l = AppLocalizations.of(context);
    _scheduler.apply(
      plan,
      title: (_) => l.laundry_reminder_title(laundryReminderLead.inMinutes),
      body: (p) => l.laundry_reminder_body(p.machineName, _hhmm(p.startsAt)),
    );
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  // --- Sessão: permissão e token ---------------------------------------------

  bool get _isApproved =>
      ref.read(currentProfileProvider).value?.isApproved ?? false;

  Future<void> _onSessionMaybeReady() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      _registeredFor = null;
      return;
    }
    if (!_isApproved) return;

    final route = _pendingRoute;
    if (route != null) {
      _pendingRoute = null;
      _openRoute(route);
    }

    if (_registeredFor == userId) return;
    _registeredFor = userId;

    if (_localReady) await _local.requestPermission();
    if (!_pushReady || !mounted) return;
    // O FCM pode já ter registrado na abertura (auto-init); o FID ficou
    // guardado e sobe agora. O `requestRegistration` cobre o caso contrário:
    // o FID chega por `registrations`, que `_registerToken` escuta.
    final id = _push.currentId;
    if (id != null) await _registerToken(id);
    await _push.requestRegistration();
  }

  Future<void> _registerToken(String token) async {
    if (ref.read(currentUserIdProvider) == null) return;
    try {
      await _push.register(token);
    } catch (e) {
      // Sem rede, por exemplo. Na próxima abertura tenta de novo.
      _registeredFor = null;
      debugPrint('Push: aparelho não registrado (${e.runtimeType}).');
    }
  }

  // --- Push recebido e notificação tocada ------------------------------------

  void _onForegroundPush(PushEvent event) {
    // O aviso novo já existe no servidor; sincronizar agora faz ele aparecer
    // na tela Início sem a pessoa puxar para atualizar.
    unawaited(ref.read(syncStatusProvider.notifier).pullAll());

    // No iOS o próprio sistema mostra (`setForegroundNotification
    // PresentationOptions`); mostrar aqui também duplicaria.
    if (defaultTargetPlatform != TargetPlatform.android || !_localReady) {
      return;
    }
    final route = event.route;
    if (route == null) return;
    final l = AppLocalizations.of(context);
    unawaited(
      _local.showAnnouncement(
        id: stableNotificationId(route),
        title: event.title ?? l.notification_announcement_fallback_title,
        body: event.body ?? '',
        payload: 'route:$route',
      ),
    );
  }

  void _openPayload(String payload) {
    if (payload.startsWith(laundryPayloadPrefix)) {
      _openRoute(Routes.escalas, replace: true);
    } else if (payload.startsWith('route:')) {
      _openRoute(payload.substring('route:'.length));
    }
  }

  void _openRoute(String? route, {bool replace = false}) {
    if (route == null || !mounted) return;
    if (ref.read(currentUserIdProvider) == null || !_isApproved) {
      // Ainda no splash ou no login: o router mandaria para lá de qualquer
      // jeito. Guarda e abre quando a sessão aprovada chegar.
      _pendingRoute = route;
      return;
    }
    // O aviso pode ter chegado por push há segundos e ainda não estar no
    // cache; a tela de detalhe espera o sync (ver `AnnouncementDetailScreen`).
    unawaited(ref.read(syncStatusProvider.notifier).pullAll());
    final router = ref.read(routerProvider);
    if (replace) {
      router.go(route);
    } else {
      router.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<PlannedReminder>?>(
      plannedLaundryRemindersProvider,
      (_, next) => _applyReminders(next),
    );
    ref.listen(
      currentUserIdProvider,
      (_, _) => unawaited(_onSessionMaybeReady()),
    );
    ref.listen(
      currentProfileProvider,
      (_, _) => unawaited(_onSessionMaybeReady()),
    );
    return widget.child;
  }
}
