/// Client mirror of the `copy_settings` contract.
///
/// `supabase/functions/copy-signal/shared.ts` documents its defaults as
/// "mirrored by `CopySettings` in Dart" — this is that mirror, and
/// `test/copy_policy_test.dart` pins the two sides against each other. An
/// ABSENT `copy_settings` row means exactly these defaults (index.ts falls
/// back to `DEFAULT_SETTINGS`, and migration 0009 gives the columns the same
/// column defaults), so "no row" and "row at defaults" are one contract.
///
/// Paper is the default posture everywhere: consent OFF, kill switch OFF,
/// conservative caps. The guardrail POLICY lives server-side in
/// `evaluateAccount` (shared.ts); this class only stores the facts, plus the
/// risk-slider bounds both sides clamp to.
class CopySettings {
  const CopySettings({
    this.liveConsent = false,
    this.killSwitch = false,
    this.maxLots = defaultMaxLots,
    this.maxConcurrentFollows = defaultMaxConcurrentFollows,
  });

  /// Server defaults (DEFAULT_SETTINGS in shared.ts), verbatim.
  static const bool defaultLiveConsent = false;
  static const bool defaultKillSwitch = false;
  static const double defaultMaxLots = 5.0;
  static const int defaultMaxConcurrentFollows = 5;

  /// Risk-slider band. The server clamps `risk_pct` into the same interval
  /// (`clampRiskPct`), so a preview the sheet accepted can never be resized
  /// to something else by the clamp.
  static const double defaultRiskPct = 1.0;
  static const double minRiskPct = 0.25;
  static const double maxRiskPct = 5.0;

  /// Mirrors `MAX_ACCOUNTS_PER_REQUEST` — the copy sheet enforces it before
  /// the request is ever built, so an over-long list is refused locally
  /// rather than at the function.
  static const int maxAccountsPerRequest = 10;

  /// The state an absent row represents.
  static const CopySettings defaults = CopySettings();

  final bool liveConsent;
  final bool killSwitch;
  final double maxLots;
  final int maxConcurrentFollows;

  /// A `copy_settings` row, or the defaults when the row (or any field) is
  /// absent — the same fallback index.ts applies server-side. Non-positive or
  /// non-finite caps fall back too: the server refuses to use them
  /// (`Number(s.max_lots) > 0 ? ... : DEFAULT_SETTINGS`), so a client that
  /// read them literally would preview `maxLots` refusals the server never
  /// issues. Matching the fallback keeps preview and placement on one value.
  factory CopySettings.fromJson(Map<String, dynamic> json) => CopySettings(
        liveConsent: json['live_consent'] == true,
        killSwitch: json['kill_switch'] == true,
        maxLots: _positiveOr(json['max_lots'] as num?, defaultMaxLots),
        maxConcurrentFollows:
            _positiveIntOr(json['max_concurrent_follows'] as num?,
                defaultMaxConcurrentFollows,), 
      );

  static double _positiveOr(num? v, double fallback) {
    final double? d = v?.toDouble();
    return d != null && d.isFinite && d > 0 ? d : fallback;
  }

  static int _positiveIntOr(num? v, int fallback) {
    final double? d = v?.toDouble();
    return d != null && d.isFinite && d > 0 ? d.round() : fallback;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'live_consent': liveConsent,
        'kill_switch': killSwitch,
        'max_lots': maxLots,
        'max_concurrent_follows': maxConcurrentFollows,
      };

  /// The same row with one field changed — how the settings screen edits a
  /// single guardrail without ever constructing a half-filled row.
  CopySettings copyWith({
    bool? liveConsent,
    bool? killSwitch,
    double? maxLots,
    int? maxConcurrentFollows,
  }) =>
      CopySettings(
        liveConsent: liveConsent ?? this.liveConsent,
        killSwitch: killSwitch ?? this.killSwitch,
        maxLots: maxLots ?? this.maxLots,
        maxConcurrentFollows: maxConcurrentFollows ?? this.maxConcurrentFollows,
      );

  /// Validation for the editable caps, mirroring the server's own acceptance
  /// rule (`index.ts`: a value is used only when it is finite and `> 0`,
  /// otherwise `DEFAULT_SETTINGS` answers). The client refuses to WRITE a
  /// value the server would throw away, so a saved cap is always the stored
  /// cap — no silent fallback to 5.0 behind the trader's back.
  /// [isValidMaxConcurrentFollows] additionally requires a whole number,
  /// because the `max_concurrent_follows` column is an `int`.
  static bool isValidMaxLots(num? v) =>
      v != null && v.isFinite && v > 0 && v <= maxLotsCeiling;

  static bool isValidMaxConcurrentFollows(num? v) =>
      v != null && v.isFinite && v > 0 && v == v.roundToDouble();

  /// UI ceiling for the lot cap. The server accepts any positive number, but
  /// a cap this high can never bind on any account a retail trader is likely
  /// to connect, so the band exists purely to catch a fat-fingered zero or a
  /// stray decimal — it is an input guard, not a policy.
  static const double maxLotsCeiling = 100.0;

  /// Finite-or-default, clamped into [minRiskPct, maxRiskPct], 2dp — the
  /// shape of `clampRiskPct` in shared.ts. Dart inputs are typed (`num?`),
  /// so the server's string-coercion branch has no client equivalent: the
  /// slider is the only producer and it never emits a string.
  static double clampRiskPct(num? raw) {
    final double? n = raw?.toDouble();
    if (n == null || !n.isFinite) return defaultRiskPct;
    if (n < minRiskPct) return minRiskPct;
    if (n > maxRiskPct) return maxRiskPct;
    // Mirrors `Math.round(n * 100) / 100` in shared.ts: round half away from
    // zero. Values reaching this point are already inside (min, max), so the
    // positive-only branch of that rule is the whole rule.
    return (n * 100).roundToDouble() / 100;
  }
}