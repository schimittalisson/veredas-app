import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:veredas/core/config/env.dart';

/// Um push recebido, reduzido ao que o app usa.
class PushEvent {
  const PushEvent({required this.data, this.title, this.body});

  final Map<String, String> data;
  final String? title;
  final String? body;

  /// Rota a abrir quando a pessoa toca na notificação, ou null.
  String? get route => switch (data['type']) {
        'announcement' when data['id'] != null => '/aviso?id=${data['id']}',
        _ => null,
      };
}

/// Push remoto (FCM). Interface para os testes não dependerem do Firebase.
abstract class PushMessaging {
  /// Sobe o Firebase. Devolve `false` quando o push não está configurado
  /// neste build (sem os `FIREBASE_*` no dart-define) — o resto do app segue.
  Future<bool> init();

  /// Identificador deste aparelho no FCM — o **FID** (Firebase Installation
  /// ID), não o antigo "registration token", que o `firebase_messaging` 17
  /// depreciou. É para ele que a Edge Function envia (`message.fid`). Null
  /// enquanto o FCM não terminou o registro.
  String? get currentId;

  /// Emite o FID a cada registro (na abertura, a cada [requestRegistration]
  /// e quando o FCM renova a instalação).
  Stream<String> get registrations;

  /// Pede ao FCM que registre o aparelho. O resultado chega por
  /// [registrations].
  Future<void> requestRegistration();

  /// Tira o aparelho do FCM. Mensagens enviadas ao FID antigo passam a
  /// falhar, o que impede o celular de continuar recebendo depois do logout
  /// mesmo que a remoção no servidor tenha falhado.
  Future<void> deleteRegistration();

  /// Push recebido com o app aberto.
  Stream<PushEvent> get foregroundMessages;

  /// Push tocado com o app em segundo plano.
  Stream<PushEvent> get openedMessages;

  /// Push que abriu o app fechado.
  Future<PushEvent?> initialMessage();

  /// Registra e remove o FID no Supabase (RPCs da migration
  /// 20261104000200). Separado do FCM para a ordem do logout ficar explícita.
  Future<void> register(String fid);
  Future<void> unregister(String fid);
}

/// Usado quando o Firebase não está configurado e nos testes.
class NoopPushMessaging implements PushMessaging {
  const NoopPushMessaging();

  @override
  Future<bool> init() async => false;
  @override
  String? get currentId => null;
  @override
  Stream<String> get registrations => const Stream.empty();
  @override
  Future<void> requestRegistration() async {}
  @override
  Future<void> deleteRegistration() async {}
  @override
  Stream<PushEvent> get foregroundMessages => const Stream.empty();
  @override
  Stream<PushEvent> get openedMessages => const Stream.empty();
  @override
  Future<PushEvent?> initialMessage() async => null;
  @override
  Future<void> register(String fid) async {}
  @override
  Future<void> unregister(String fid) async {}
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging(this._client);

  final SupabaseClient _client;
  bool _ready = false;
  String? _currentId;
  final _registrations = StreamController<String>.broadcast();

  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  @override
  Future<bool> init() async {
    if (_ready) return true;
    if (!Env.firebaseConfiguredFor(ios: _isIos)) return false;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: _isIos ? Env.firebaseApiKeyIos : Env.firebaseApiKeyAndroid,
            appId: _isIos ? Env.firebaseAppIdIos : Env.firebaseAppIdAndroid,
            messagingSenderId: Env.firebaseSenderId,
            projectId: Env.firebaseProjectId,
            iosBundleId: _isIos ? 'br.com.veredas.app' : null,
          ),
        );
      }
      // No iOS o sistema mostra o push mesmo com o app aberto; sem isto ele
      // seria engolido. No Android quem mostra é o `NotificationCoordinator`,
      // pela notificação local — o FCM não mostra nada em primeiro plano.
      await _fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      // O listener vem antes de qualquer `register()`: com o auto-init
      // ligado (padrão) o FCM registra sozinho na abertura, e um FID emitido
      // antes da assinatura se perderia.
      _fm.onRegistered.listen((fid) {
        _currentId = fid;
        _registrations.add(fid);
      });
      _fm.onUnregistered.listen((_) => _currentId = null);
      _ready = true;
      return true;
    } catch (e) {
      // Push é acessório: uma configuração errada não pode impedir o app de
      // abrir. Só o tipo vai para o log (AGENTS.md §8.6).
      debugPrint('Push desligado: falha ao iniciar o Firebase '
          '(${e.runtimeType}).');
      return false;
    }
  }

  @override
  String? get currentId => _currentId;

  @override
  Stream<String> get registrations => _registrations.stream;

  @override
  Future<void> requestRegistration() async {
    if (!_ready) return;
    try {
      await _fm.register();
    } catch (e) {
      // Sem rede, ou o APNs ainda não entregou o token dele (iOS). O FCM
      // tenta de novo sozinho e o FID chega por `registrations`.
      debugPrint('Push: registro adiado (${e.runtimeType}).');
    }
  }

  @override
  Future<void> deleteRegistration() async {
    if (!_ready) return;
    try {
      await _fm.unregister();
    } catch (_) {}
    _currentId = null;
  }

  @override
  Stream<PushEvent> get foregroundMessages =>
      _ready ? FirebaseMessaging.onMessage.map(_toEvent) : const Stream.empty();

  @override
  Stream<PushEvent> get openedMessages => _ready
      ? FirebaseMessaging.onMessageOpenedApp.map(_toEvent)
      : const Stream.empty();

  @override
  Future<PushEvent?> initialMessage() async {
    if (!_ready) return null;
    final m = await _fm.getInitialMessage();
    return m == null ? null : _toEvent(m);
  }

  // Exceção consciente à regra "toda escrita passa pelo outbox" (AGENTS.md
  // §6.8): o FID é do aparelho, não um dado que a pessoa vê, e não há o que
  // mostrar de forma otimista. Se falhar, a próxima abertura registra de novo.
  @override
  Future<void> register(String fid) => _client.rpc(
        'register_push_device',
        params: {'p_fid': fid, 'p_platform': _isIos ? 'ios' : 'android'},
      );

  @override
  Future<void> unregister(String fid) =>
      _client.rpc('unregister_push_device', params: {'p_fid': fid});

  static PushEvent _toEvent(RemoteMessage m) => PushEvent(
        data: {
          for (final e in m.data.entries) e.key: '${e.value}',
        },
        title: m.notification?.title,
        body: m.notification?.body,
      );
}
