import 'dart:async';

/// A push that arrived while the app was in the foreground. Background/terminated notifications
/// are rendered by the OS, so we only ever handle these ourselves.
class RemoteAlert {
  const RemoteAlert({
    required this.title,
    required this.body,
    this.data = const <String, dynamic>{},
  });

  final String title;
  final String body;
  final Map<String, dynamic> data;
}

/// FCM plumbing for the **server-driven** alerts described in `docs/BACKEND_SCHEMA.md`: the
/// `guard-check` Edge Function runs every minute and pushes at 70% / 90%.
///
/// The client deliberately does *not* build its own system notifications here — that would need
/// `flutter_local_notifications` and would duplicate logic the backend already owns. Nothing in
/// this file carries broker credentials or order intent.
abstract class PushService {
  /// False when push cannot work (no Firebase config, unsupported platform, init failed).
  bool get isAvailable;

  /// Idempotent. Must never throw — a push failure must not break the guard.
  Future<void> init();

  Future<bool> requestPermission();

  /// Subscribes this device to one account's alerts.
  Future<void> subscribeToAccount(String accountId);

  /// Foreground messages. Background ones are drawn by the OS.
  Stream<RemoteAlert> get alerts;
}

/// Records subscriptions and lets tests emit foreground alerts, with no platform channels
/// involved. Used in mock mode and in unit tests.
class MockPushService implements PushService {
  MockPushService();

  /// Every account this device subscribed to, in order.
  final List<String> subscriptions = <String>[];

  final StreamController<RemoteAlert> _controller =
      StreamController<RemoteAlert>.broadcast();

  final bool _permissionGranted = true;

  @override
  bool get isAvailable => true;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => _permissionGranted;

  @override
  Future<void> subscribeToAccount(String accountId) async {
    if (!subscriptions.contains(accountId)) subscriptions.add(accountId);
  }

  @override
  Stream<RemoteAlert> get alerts => _controller.stream;

  /// Test hook: pretend the server pushed something.
  void emit(RemoteAlert alert) => _controller.add(alert);

  Future<void> dispose() => _controller.close();
}
