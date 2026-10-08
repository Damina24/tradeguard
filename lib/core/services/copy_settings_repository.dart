import '../models/copy_settings.dart';

/// The trader's own `copy_settings` row (migration 0009, task 3.6): live
/// consent, kill switch, and the two caps `evaluateAccount` reads before it
/// places anything.
///
/// An ABSENT row is part of the contract, not an error: `index.ts` falls back
/// to `DEFAULT_SETTINGS` when the row is missing, and [fetchCopySettings]
/// returns [CopySettings.defaults] in the same case, so "no row" and "row at
/// defaults" are one state on both sides of the wire. Writes are own-row only
/// (RLS `own copy settings`: `auth.uid() = user_id` on both USING and WITH
/// CHECK), and the Edge Function reads the same row under the service role —
/// neither side trusts a value the client merely holds in memory.
abstract class CopySettingsRepository {
  /// The stored row, or [CopySettings.defaults] when none exists yet.
  Future<CopySettings> fetchCopySettings();

  /// Upserts the caller's own row. The whole quartet is written every time:
  /// a partial write would leave the server reading a mix of old and new
  /// guardrails.
  Future<void> saveCopySettings(CopySettings settings);
}

/// In-memory `copy_settings` for mock mode: one row per repository instance,
/// absent until first saved (which is exactly how the real table behaves for
/// a fresh trader). [initial] exists so tests can start from a non-default
/// posture — kill switch ON, consent granted — without a database.
class MockCopySettingsRepository implements CopySettingsRepository {
  MockCopySettingsRepository([CopySettings? initial]) : _row = initial;

  CopySettings? _row;

  @override
  Future<CopySettings> fetchCopySettings() async =>
      _row ?? CopySettings.defaults;

  @override
  Future<void> saveCopySettings(CopySettings settings) async {
    _row = settings;
  }
}
