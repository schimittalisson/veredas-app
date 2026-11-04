import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Canais do Android. O id é o que o servidor manda no push
/// (`android.notification.channel_id` em `notify-announcement/fcm.ts`) —
/// mudar um exige mudar o outro.
const announcementsChannelId = 'announcements';
const laundryChannelId = 'laundry';

/// Notificações locais: agendar o lembrete da lavanderia e mostrar o push que
/// chega com o app aberto no Android (o FCM não mostra nada nesse caso).
///
/// Interface para os testes não dependerem do plugin, que fala com o sistema
/// por canal de plataforma.
abstract class LocalNotifications {
  /// Prepara o plugin e os canais. Não pede permissão.
  Future<void> init({
    required String announcementsChannelName,
    required String laundryChannelName,
  });

  /// Pede permissão para notificar (Android 13+ e iOS). Devolve se foi dada.
  Future<bool> requestPermission();

  /// `payload`s das notificações agendadas e ainda não disparadas, por id.
  Future<Map<int, String?>> pending();

  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
  });

  Future<void> cancel(int id);

  /// Mostra agora, no canal de avisos.
  Future<void> showAnnouncement({
    required int id,
    required String title,
    required String body,
    required String payload,
  });

  /// `payload` de cada notificação local tocada pela pessoa.
  Stream<String> get taps;

  /// `payload` da notificação local que abriu o app, se foi isso que o abriu.
  Future<String?> launchPayload();
}

class PluginLocalNotifications implements LocalNotifications {
  PluginLocalNotifications([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<String>.broadcast();
  bool _ready = false;
  String _announcementsChannelName = '';
  String _laundryChannelName = '';

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<void> init({
    required String announcementsChannelName,
    required String laundryChannelName,
  }) async {
    if (_ready) return;
    _announcementsChannelName = announcementsChannelName;
    _laundryChannelName = laundryChannelName;

    // O agendamento usa `TZDateTime`. Sem o fuso do aparelho, `tz.local` é
    // UTC e o lembrete das 14:00 tocaria às 11:00.
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        // Ícone monocromático: o ícone do launcher, colorido, vira um
        // quadrado branco na barra de status do Android.
        android: AndroidInitializationSettings('ic_notification'),
        // Nenhum pedido de permissão na inicialização: ela roda antes do
        // login, e o pedido vem depois, em contexto (`requestPermission`).
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _taps.add(payload);
      },
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        announcementsChannelId,
        announcementsChannelName,
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        laundryChannelId,
        laundryChannelName,
        importance: Importance.high,
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  @override
  Future<Map<int, String?>> pending() async {
    final list = await _plugin.pendingNotificationRequests();
    return {for (final p in list) p.id: p.payload};
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
  }) {
    return _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          laundryChannelId,
          _laundryChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // Inexato, e de propósito: o alarme exato exige SCHEDULE_EXACT_ALARM,
      // que no Android 14 começa negado e manda a pessoa para uma tela de
      // configuração. Com meia hora de antecedência, alguns minutos de
      // variação não mudam nada.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> showAnnouncement({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) {
    return _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          announcementsChannelId,
          _announcementsChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details!.notificationResponse?.payload;
  }
}
