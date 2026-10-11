import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/live_account.dart';
import '../../../core/services/supabase_service.dart';
import 'live_account_repository.dart';

/// Live account reads through the `sync-account-data` Edge Function.
///
/// The client never calls MetaAPI directly: the `METAAPI_TOKEN` lives only in the
/// function's environment (see `supabase/functions/sync-account-data/index.ts`),
/// and only the opaque `account_id` crosses the wire. Every failure is mapped to
/// a trader-safe [LiveAccountException] — a MetaAPI error body can echo the
/// account identifier back, so it is never propagated.
class SupabaseLiveAccountRepository implements LiveAccountRepository {
  SupabaseLiveAccountRepository({SupabaseService? service})
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  @override
  Future<LiveAccountData> fetchLive(String accountId) async {
    final dynamic response;
    try {
      response = await _service.client.functions
          .invoke(
            'sync-account-data',
            body: <String, dynamic>{'account_id': accountId},
          )
          .timeout(SupabaseService.networkTimeout);
    } on FunctionsHttpException catch (e) {
      throw LiveAccountException(_mapStatus(e.status));
    } catch (_) {
      // Transport failure (offline, DNS, timeout): a generic retry message, never
      // a raw socket string.
      throw const LiveAccountException(
        'Could not reach your broker. Check your connection and try again.',
      );
    }

    final Map<String, dynamic>? data = response.data as Map<String, dynamic>?;
    if (data == null) {
      throw const LiveAccountException('Your broker returned an unexpected response.');
    }
    if (data['ok'] != true) {
      throw LiveAccountException(_mapError(data['error'] as String?));
    }

    try {
      return LiveAccountData.fromJson(data);
    } catch (_) {
      throw const LiveAccountException('Your broker returned an unexpected response.');
    }
  }

  /// HTTP status → trader-safe copy. Mirrors the copy-signal repository.
  static String _mapStatus(int statusCode) {
    switch (statusCode) {
      case 401:
      case 403:
        return 'Your session expired. Sign in again.';
      case 404:
        return 'That account could not be found.';
      case 429:
      case 503:
        return 'Your broker is busy. Try again shortly.';
      case 500:
      default:
        return 'Could not load live data. Try again shortly.';
    }
  }

  /// The Edge Function's own `error` string → trader-safe copy. Known values map
  /// to specific lines; anything unknown stays generic so no server text leaks.
  static String _mapError(String? error) {
    switch (error) {
      case 'Unauthorized':
        return 'Your session expired. Sign in again.';
      case 'notConfigured':
        return 'Live data is not configured for this account yet.';
      case 'Account not found':
        return 'That account could not be found.';
      case 'notLinked':
        // Not an error: the account simply has no broker link. The UI renders a
        // grey "not linked" badge rather than a red one.
        return 'This account is not linked to a broker.';
      default:
        return 'Could not load live data. Try again shortly.';
    }
  }
}
