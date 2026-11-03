import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../firebase_options.dart';

/// Phone push notifications. Everything here is best-effort: if Firebase is unavailable
/// the app keeps working and notifications still appear inside the app.
class PushService {
  PushService._();
  static final instance = PushService._();

  bool _ready = false;
  String? _token;
  bool _listening = false;

  /// Set when the user taps a notification: the screen id to open (notices, meetings, messages, moderation).
  final ValueNotifier<String?> openTarget = ValueNotifier<String?>(null);

  /// Bumped when a notification arrives while the app is open (so the bell badge can refresh).
  final ValueNotifier<int> incoming = ValueNotifier<int>(0);

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp(options: firebaseOptions);
      _ready = true;
      FirebaseMessaging.onMessage.listen((_) => incoming.value++);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m));
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) _open(first);
    } catch (e) {
      debugPrint('Push not available: $e');
    }
  }

  void _open(RemoteMessage m) {
    final target = switch (m.data['kind']) {
      'announcement' => 'notices',
      'meeting' => 'meetings',
      'message' => 'messages',
      'message_report' => 'moderation',
      _ => null,
    };
    if (target != null) openTarget.value = target;
  }

  /// Asks for permission (Android 13+) and registers this phone for the signed-in user.
  Future<void> register() async {
    if (!_ready) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      _token = token;
      await _send(token);
      if (!_listening) {
        _listening = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((t) {
          _token = t;
          _send(t);
        });
      }
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  Future<void> _send(String token) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return;
    await client.schema(AppConfig.schema).rpc('register_device_token', params: {'p_token': token, 'p_platform': 'android'});
  }

  /// Call BEFORE signing out so this phone stops receiving the person's notifications.
  Future<void> unregister() async {
    final token = _token;
    if (!_ready || token == null) return;
    try {
      await Supabase.instance.client.schema(AppConfig.schema).rpc('remove_device_token', params: {'p_token': token});
    } catch (e) {
      debugPrint('Push unregister failed: $e');
    }
  }
}
