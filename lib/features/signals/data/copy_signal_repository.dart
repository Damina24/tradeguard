import '../domain/copy_signal.dart';

/// Writes one *paper* follow batch through the `copy-signal` Edge Function.
///
/// The client never decides the outcome: it asks the Edge Function, which
/// re-derives lots from server-side equity, re-runs every guardrail (kill
/// switch, live consent, per-account permission, ownership, max-lots, max
/// concurrent) and returns its own rows — `{ account_id, lots, status,
/// refusal }`. The sheet renders those rows and reports the refusal exactly as
/// the server named it (1:1 via [CopyRefusal.values.byName]).
///
/// Paper is the only mode this seam supports. The confirm sheet never asks
/// the trader for live consent, so `mode='live'` is not exposed to the user:
/// a live ask without stored consent is a client-side refusal, never a silent
/// downgrade (shared.ts:14-18).
abstract class CopySignalRepository {
  bool get isStubbed;

  /// Places a paper copy batch.
  ///
  /// [signalPair] and [stopPips] are the client's copy of the signal's own
  /// pair and stop distance:
  ///   * the mock repository uses them to reproduce the paper formula
  ///     deterministically (it has no database), and
  ///   * the Supabase implementation ignores them — it reads the pair from
  ///     the `signals` table itself (index.ts:200-203), which is the same
  ///     facts, sourced server-side.
  Future<CopySignalResult> placeCopySignal({
    required String signalId,
    required List<String> accountIds,
    required String signalPair,
    required double stopPips,
    required double riskPct,
    required String mode,
  });

  /// How many follows are currently open for this trader — the count
  /// `index.ts` feeds to `evaluateAccount` as `openFollows` (`signal_follows`
  /// where `copy_status` is `pending` or `placed`, scoped to the caller: the
  /// server filters by the verified JWT's user id, the client by RLS `own
  /// follows` — same rows). The preview needs it to predict `maxConcurrent`
  /// before the round trip; the server still recounts at request time, so a
  /// stale count can only cost a preview, never a placement.
  Future<int> countOpenFollows();
}
