import 'dart:async';

import '../models/guard_status.dart';
import 'guard_alerts.dart';
import 'push_service.dart';

/// A guard alert the UI can surface immediately (in-app banner / foreground toast).
class GuardAlert {
  const GuardAlert({
    required this.level,
    required this.title,
    required this.body,
    required this.at,
  });

  final GuardAlertLevel level;
  final String title;
  final String body;
  final DateTime at;
}

/// Ties guard readings to push subscription and to immediate in-app alerts.
///
/// The *system* push at 70/90 is sent server-side by `guard-check` (see `docs/BACKEND_SCHEMA.md`),
/// so all this does client-side is subscribe the device to that account's topic and raise an
/// in-app alert the moment a threshold is crossed on this device.
///
/// Framework-free so it is unit-testable without pumping a widget, and so the "have we already
/// alerted on this threshold?" decision has a single home.
class GuardAlertMonitor {
  GuardAlertMonitor({PushService? push, GuardAlertEvaluator? evaluator})
      : _push = push,
        _evaluator = evaluator ?? const GuardAlertEvaluator();

  final PushService? _push;
  final GuardAlertEvaluator _evaluator;

  final StreamController<GuardAlert> _controller =
      StreamController<GuardAlert>.broadcast();

  GuardStatus? _previous;
  String? _accountId;

  /// In-app alerts, oldest first.
  Stream<GuardAlert> get alerts => _controller.stream;

  /// The most recent alert, or null if none has fired.
  GuardAlert? lastAlert;

  GuardAlertLevel? get lastLevel => lastAlert?.level;

  DateTime? get lastSentAt => lastAlert?.at;

  /// The reading the last evaluation was compared against.
  GuardStatus? get previousStatus => _previous;

  /// Call after every guard reading. Never throws — a push failure must not break a risk surface.
  Future<void> onGuardStatus(GuardStatus status) async {
    // Thresholds are per-account, so switching accounts re-arms. This is also where we (re)subscribe
    // to that account's server-pushed alert topic.
    if (_accountId != status.account.id) {
      _accountId = status.account.id;
      _previous = null;
      await _subscribe(status.account.id);
    }

    final List<GuardAlertLevel> levels =
        _evaluator.evaluate(current: status, previous: _previous);
    _previous = status;

    for (final GuardAlertLevel level in levels) {
      final GuardAlert alert = GuardAlert(
        level: level,
        title: GuardAlertCopy.title(level),
        body: GuardAlertCopy.body(level, status.account),
        at: DateTime.now(),
      );
      lastAlert = alert;
      _controller.add(alert);
    }
  }

  Future<void> _subscribe(String accountId) async {
    final PushService? push = _push;
    if (push == null) return;
    try {
      await push.subscribeToAccount(accountId);
    } catch (_) {
      // Push is best-effort.
    }
  }

  /// Forget the previous reading so every threshold re-arms (sign-out, or an explicit reset).
  void reset() {
    _previous = null;
    _accountId = null;
    lastAlert = null;
  }

  Future<void> dispose() => _controller.close();
}
