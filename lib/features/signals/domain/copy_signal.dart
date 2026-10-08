/// The answer the `copy-signal` Edge Function returns for one confirm tap:
/// one row per requested account with the server's own lots, risk % and the
/// refusal (if any). Nothing here is computed client-side: the client prints
/// exactly what the server decided, so a preview and the follow that runs can
/// never disagree about the outcome.
///
/// The refusal strings are a closed set (lines 43-52 of `shared.ts`), and the
/// client maps them 1:1 with [CopyRefusal] — the sheet's `byName` mapping is
/// the single source of truth for both the preview refusal and a server
/// answer, so a refusal that lands on the order side is never reworded.
class CopySignalRow {
  const CopySignalRow({
    required this.accountId,
    required this.mode,
    required this.lots,
    required this.riskPct,
    required this.status,
    this.refusal,
    this.orderId,
    this.simulated,
  });

  factory CopySignalRow.fromJson(Map<String, dynamic> json) => CopySignalRow(
        accountId: json['account_id'] as String,
        mode: json['mode'] as String,
        lots: (json['lots'] as num).toDouble(),
        riskPct: (json['risk_pct'] as num).toDouble(),
        status: json['status'] as String,
        refusal: json['refusal'] as String?,
        orderId: json['order_id'] as String?,
        simulated: json['simulated'] as bool?,
      );

  final String accountId;
  final String mode;
  final double lots;
  final double riskPct;
  final String status;
  final String? refusal;
  final String? orderId;
  final bool? simulated;

  bool get isPlaced => status == 'placed';
  bool get isFailed => status == 'failed';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'account_id': accountId,
        'mode': mode,
        'lots': lots,
        'risk_pct': riskPct,
        'status': status,
        if (refusal != null) 'refusal': refusal,
        if (orderId != null) 'order_id': orderId,
        if (simulated != null) 'simulated': simulated,
      };
}

/// The full batch answer from the `copy-signal` Edge Function: `{ ok, mode, results }`.
class CopySignalResult {
  const CopySignalResult({
    required this.ok,
    required this.mode,
    required this.results,
  });

  factory CopySignalResult.fromJson(Map<String, dynamic> json) =>
      CopySignalResult(
        ok: json['ok'] as bool,
        mode: json['mode'] as String,
        results: (json['results'] as List<dynamic>)
            .map((e) => CopySignalRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final bool ok;
  final String mode;
  final List<CopySignalRow> results;

  int get placedCount => results.where((r) => r.isPlaced).length;
  int get failedCount => results.where((r) => r.isFailed).length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ok': ok,
        'mode': mode,
        'results': results.map((r) => r.toJson()).toList(),
      };
}

/// Why one account's follow could not be placed.
///
/// Exactly the strings from `shared.ts` (lines 43-52): the client maps these
/// 1:1 to [CopyRefusal] with `CopyRefusal.values.byName`, so a server refusal
/// is never reworded and a preview refusal is never a guess about server-side
/// facts the client does not hold.
enum CopySignalFailure {
  unreachable('Could not reach the copy service — check your connection and try again.'),
  unauthorized('Sign in to copy signals.'),
  forbidden('That copy request is not available.'),
  unavailable('The copy service is unavailable — try again.'),
  malformed('The copy service sent an unreadable answer.'),
  server('The copy service could not complete the request.'),
  invalidRequest('The copy request was not understood.'),
  signalMissing('That signal is no longer available — refresh the feed and try again.'),
  unableToPlace('One of the accounts refused to place this copy.');

  const CopySignalFailure(this.message);

  final String message;
}

/// A failed call to the `copy-signal` Edge Function.
///
/// Carries a failure, never a raw server message: a PostgREST error can name
/// tables and columns, and nothing it says is worth showing a trader.
class CopySignalException implements Exception {
  const CopySignalException(this.failure);

  final CopySignalFailure failure;

  String get message => failure.message;

  @override
  String toString() => 'CopySignalException($failure)';
}
