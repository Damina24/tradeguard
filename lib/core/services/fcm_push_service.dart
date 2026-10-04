import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_service.dart';

/// Firebase Cloud Messaging implementation.
///
/// Firebase needs `google-services.json` / `GoogleService-Info.plist`, which is a human gate — so
/// every entry point swallows its own failure and simply reports [isAvailable] as false. A missing
/// push setup must degrade the app, never crash it.
class FcmPushService implements PushService {
  FcmPushService();

  /// Channel the `guard-check` function targets; matches the AndroidManifest default channel id.
  static const String channelId = 'guard_alerts';

  final StreamController<RemoteAlert> _alerts =
      StreamController<RemoteAlert>.broadcast();

  bool _ready = false;

  @override
  bool get isAvailable => _ready;

  @override
  Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onMessage.listen(_onMessage);
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  void _onMessage(RemoteMessage message) {
    final RemoteNotification? n = message.notification;
    _alerts.add(
      RemoteAlert(
        title: n?.title ?? 'TradeGuard',
        body: n?.body ?? '',
        data: message.data,
      ),
    );
  }

  @override
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final NotificationSettings settings =
          await FirebaseMessaging.instance.requestPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> subscribeToAccount(String accountId) async {
    if (!_ready) return;
    try {
      await FirebaseMessaging.instance.subscribeToTopic(_topic(accountId));
    } catch (_) {
      // Subscription failures are not worth surfacing to a trader mid-session.
    }
  }

  @override
  Stream<RemoteAlert> get alerts => _alerts.stream;

  /// FCM topics only allow `[a-zA-Z0-9-_.~%]`, and the `guard_` prefix keeps guard topics separate
  /// from any future product messaging.
  static String _topic(String accountId) =>
      'guard_${accountId.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '-')}';

  Future<void> dispose() => _alerts.close();
}
