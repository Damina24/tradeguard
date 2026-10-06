import '../../../core/models/signal.dart';

/// Read access to the `signals` table.
///
/// The seam exists for one reason: **no caller may choose whose signals to
/// read.** There is deliberately no `userId` parameter on any method. Signals
/// are operator-posted rows readable by any signed-in trader (migration 0002
/// policy `"signals read"`); identity comes from the session inside the
/// implementation, never from a widget. A caller that wanted another trader's
/// private data cannot express that request, so there is nothing to get wrong.
///
/// Values are the table's own columns; see [Signal] for what each one means.
abstract class SignalRepository {
  /// True when signals come from the offline seed rather than the backend, so
  /// the screen can say so honestly instead of implying live operator posts.
  bool get isStubbed;

  /// Signals newest first.
  ///
  /// Throws [SignalDataException] on a backend failure so the UI can show an
  /// error state. Returning an empty list instead would render as "no signals
  /// posted", which is a different and misleading claim.
  Future<List<Signal>> fetchSignals({int limit = 100});
}

/// Thrown by repositories when the backend cannot be read or a row cannot be
/// understood.
///
/// Distinct from an empty feed: this means the read failed, which is a
/// condition the trader needs to hear about rather than have papered over.
/// The UI shows generic "could not load" copy and never renders the raw
/// message, because a PostgREST error can name tables and columns.
class SignalDataException implements Exception {
  const SignalDataException(this.message);

  final String message;

  @override
  String toString() => 'SignalDataException: $message';
}
