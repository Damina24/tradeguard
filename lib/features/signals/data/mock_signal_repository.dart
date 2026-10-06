import '../../../core/models/signal.dart';
import '../../../core/services/mock_data.dart';
import 'signal_repository.dart';

/// Offline signals, seeded with the same deterministic data the Phase 0 screen
/// rendered.
///
/// The seed is returned as-is rather than recomputed: inventing signal rows
/// from trades would be a second, hidden claim that those signals were
/// actually posted. Its output is labelled `OFFLINE DEMO` on the screen,
/// because an unlabelled demo feed is indistinguishable from live operator
/// posts — exactly the impression a compliance-sensitive product must not give.
class MockSignalRepository implements SignalRepository {
  MockSignalRepository({List<Signal>? signals})
      : _signals = signals ?? MockData.signals();

  final List<Signal> _signals;

  @override
  bool get isStubbed => true;

  @override
  Future<List<Signal>> fetchSignals({int limit = 100}) async =>
      List<Signal>.unmodifiable(_signals.take(limit));
}
