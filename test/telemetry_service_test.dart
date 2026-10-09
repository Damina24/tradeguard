import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/services/telemetry_service.dart';

/// Records every event the telemetry seam forwards, so the test can assert the
/// exact name + parameters without a Firebase platform channel.
class _FakeAnalyticsLogger implements AnalyticsLogger {
  final List<(String, Map<String, Object>?)> calls =
      <(String, Map<String, Object>?)>[];

  @override
  Future<void> logEvent(String name, Map<String, Object>? parameters) async {
    calls.add((name, parameters));
  }
}

/// A logger that always throws, proving a failing analytics backend can never
/// crash the caller.
class _ThrowingAnalyticsLogger implements AnalyticsLogger {
  @override
  Future<void> logEvent(String name, Map<String, Object>? parameters) async {
    throw StateError('analytics offline');
  }
}

void main() {
  tearDown(TelemetryService.instance.debugDetach);

  test('logEvent forwards the event name to the analytics logger', () async {
    final _FakeAnalyticsLogger logger = _FakeAnalyticsLogger();
    TelemetryService.instance.debugAttachLogger(logger);

    TelemetryService.instance.logEvent('copy_signal_attempted');
    // Drain the microtask queue so the unawaited emit completes.
    await Future<void>.delayed(Duration.zero);

    expect(logger.calls, hasLength(1));
    expect(logger.calls.single.$1, 'copy_signal_attempted');
  });

  test('logEvent passes parameters through unchanged (no PII injected)',
      () async {
    final _FakeAnalyticsLogger logger = _FakeAnalyticsLogger();
    TelemetryService.instance.debugAttachLogger(logger);

    TelemetryService.instance
        .logEvent('paywall_viewed', <String, Object>{'plan': 'annual'});
    await Future<void>.delayed(Duration.zero);

    final (String name, Map<String, Object>? params) = logger.calls.single;
    expect(name, 'paywall_viewed');
    expect(params, <String, Object>{'plan': 'annual'});
  });

  test('a throwing analytics backend never propagates to the caller', () async {
    TelemetryService.instance.debugAttachLogger(_ThrowingAnalyticsLogger());

    // Must not throw, synchronously or asynchronously.
    expect(
      () => TelemetryService.instance.logEvent('guard_stop_pressed'),
      returnsNormally,
    );
    await Future<void>.delayed(Duration.zero);
  });

  test('logEvent is a silent no-op before telemetry is attached', () async {
    // No logger attached (mock mode / tests): calling must not throw.
    expect(
      () => TelemetryService.instance.logEvent('anything'),
      returnsNormally,
    );
    await Future<void>.delayed(Duration.zero);
  });
}
