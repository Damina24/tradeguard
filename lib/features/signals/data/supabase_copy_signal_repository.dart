import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tradeguard/core/models/copy_settings.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/services/telemetry_service.dart';
import '../domain/copy_signal.dart';
import 'copy_signal_repository.dart';

/// Places paper copies through the `copy-signal` Edge Function (task 3.5).
///
/// The client never decides the outcome. It asks the Edge Function, which
/// re-derives lots from server-side equity, re-runs every guardrail (kill
/// switch, live consent, per-account permission, ownership, max-lots, max
/// concurrent) and returns its own `{ account_id, lots, status, refusal }`
/// rows. The confirm sheet renders those rows and reports each refusal using
/// the server's exact name, mapped 1:1 to [CopyRefusal].
///
/// Paper is the only mode this seam supports. The confirm sheet never asks
/// the trader for live consent, so a `mode='live'` ask without stored
/// consent is a client-side refusal — never a silent downgrade (shared.ts:
/// 14-18).
class SupabaseCopySignalRepository implements CopySignalRepository {
  SupabaseCopySignalRepository({SupabaseService? service})
    : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  @override
  bool get isStubbed => false;

  @override
  Future<CopySignalResult> placeCopySignal({
    required String signalId,
    required List<String> accountIds,
    required String signalPair,
    required double stopPips,
    required double riskPct,
    required String mode,
  }) async {
    // Coarse, non-PII: a copy was attempted. No signal id, account id, lot
    // size or equity is sent — only the fact that the flow was entered.
    TelemetryService.instance.logEvent('copy_signal_attempted');
    final dynamic response;
    try {
      response = await _service.client.functions.invoke(
        'copy-signal',
        body: <String, dynamic>{
          'signal_id': signalId,
          'account_ids': List<String>.unmodifiable(accountIds),
          'risk_pct': CopySettings.clampRiskPct(riskPct),
          'mode': mode,
        },
      );
    } on FunctionsHttpException catch (e) {
      throw CopySignalException(_classify(e.status));
    } catch (_) {
      throw const CopySignalException(CopySignalFailure.unreachable);
    }

    final Map<String, dynamic>? data = response.data as Map<String, dynamic>?;
    if (data == null) {
      throw const CopySignalException(CopySignalFailure.malformed);
    }
    if (data['ok'] != true) {
      throw CopySignalException(
        data['ok'] == false
            ? _mapError(data['error'] as String?)
            : CopySignalFailure.malformed,
      );
    }

    try {
      return CopySignalResult.fromJson(data);
    } catch (_) {
      throw const CopySignalException(CopySignalFailure.malformed);
    }
  }

  /// Translates the Edge Function's HTTP status into a trader-safe failure.
  static CopySignalFailure _classify(int statusCode) {
    switch (statusCode) {
      case 400:
      case 422:
        return CopySignalFailure.invalidRequest;
      case 401:
        return CopySignalFailure.unauthorized;
      case 403:
        return CopySignalFailure.forbidden;
      case 404:
        return CopySignalFailure.signalMissing;
      case 429:
      case 503:
        return CopySignalFailure.unavailable;
      case 500:
        return CopySignalFailure.server;
      default:
        return CopySignalFailure.unreachable;
    }
  }

  @override
  Future<int> countOpenFollows() async {
    // Exact count of the caller's open follows. RLS `own follows` scopes the
    // rows the same way index.ts scopes them by verified JWT user id, and
    // `count` respects the filters while ignoring modifiers, so the number is
    // the same one evaluateAccount receives server-side.
    final dynamic res = await _service.client
        .from('signal_follows')
        .select('id')
        .inFilter('copy_status', <String>['pending', 'placed'])
        .count(CountOption.exact);
    final int? count = res.count as int?;
    return count ?? 0;
  }

  /// Translates the Edge Function's batch-level `error` string into a
  /// trader-safe failure. Every known batch error is sent with a non-2xx
  /// status, so [FunctionsHttpException] + [_classify] normally answer first;
  /// this path exists for a proxy that rewrites the status, and it still never
  /// leaks the raw string — the sheet always shows [CopySignalFailure]'s own
  /// wording. Per-account refusals never arrive here: they travel in
  /// `results[].refusal` and are mapped by the sheet with
  /// [CopyRefusal.values.byName].
  static CopySignalFailure _mapError(String? error) {
    switch (error) {
      case 'Unauthorized':
        return CopySignalFailure.unauthorized;
      case 'Signal not found':
        return CopySignalFailure.signalMissing;
      case 'notConfigured':
        return CopySignalFailure.unavailable;
      case 'server':
        return CopySignalFailure.server;
      case 'Method not allowed':
      case 'Invalid body':
      case 'Expected a JSON body.':
      case 'signal_id is required.':
      case 'account_ids must be a non-empty array.':
      case 'account_ids is capped at 10.':
      case 'account_ids must contain uuids only.':
        return CopySignalFailure.invalidRequest;
      default:
        return CopySignalFailure.server;
    }
  }
}
