import '../domain/pattern_row.dart';

/// Read access to the `v_patterns` SQL view.
///
/// The seam exists for one reason: **no caller may choose whose data to read.**
/// There is deliberately no `userId` parameter on any method here. Identity comes
/// from the authenticated session only — `authProvider` in live mode, the demo
/// identity in mock mode — and Postgres row-level security on `trades` is the
/// real enforcement. A caller that wanted someone else's patterns cannot express
/// that request, so there is nothing to get wrong.
///
/// Values are the view's own aggregates; see [PatternRow] for what each one means.
abstract class PatternRepository {
  /// Rows of `v_patterns` belonging to the signed-in trader.
  ///
  /// Throws on a backend failure so the UI can show an error state. Returning an
  /// empty list instead would render as "you have no patterns", which is a
  /// different and misleading claim.
  Future<List<PatternRow>> fetchPatterns();
}

/// Thrown by repositories when a row cannot be understood.
///
/// Distinct from a transport failure: this means the backend sent something that
/// does not match the view contract, which is a bug to surface, not an empty
/// journal. The UI shows the same generic "could not load" copy for both and never
/// renders the raw message, because a PostgREST error can name tables and columns.
class PatternDataException implements Exception {
  const PatternDataException(this.message);

  final String message;

  @override
  String toString() => 'PatternDataException: $message';
}