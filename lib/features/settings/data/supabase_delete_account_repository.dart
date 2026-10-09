import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../domain/delete_account.dart';
import 'delete_account_repository.dart';

/// Supabase-backed account deletion: invokes the `delete-account` Edge Function.
///
/// The server owns the whole deletion — it authenticates the caller with GoTrue from their own
/// session, deletes their rows child-first, removes their `trade-screenshots` objects by uid prefix
/// and finally removes the auth user. The client sends no body (the uid comes from the verified
/// JWT, never from the request) and only reports the server's verdict. Every failure is mapped onto
/// a [DeleteAccountFailure] so a PostgREST error — which can name tables and columns — is never
/// shown to a trader.
class SupabaseDeleteAccountRepository implements DeleteAccountRepository {
  SupabaseDeleteAccountRepository({SupabaseService? service})
    : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  @override
  bool get isStubbed => false;

  @override
  Future<void> deleteAccount() async {
    final dynamic response;
    try {
      // No body: the caller's identity comes from the verified bearer token, not the request.
      response = await _service.client.functions.invoke('delete-account');
    } on FunctionsHttpException catch (e) {
      throw DeleteAccountException(_classify(e.status));
    } catch (_) {
      throw const DeleteAccountException(DeleteAccountFailure.unreachable);
    }

    final Map<String, dynamic>? data = response.data as Map<String, dynamic>?;
    // A 2xx with no parseable body is treated as success only if it carries the ok flag; anything
    // else is a malformed answer we refuse to interpret as "deleted".
    if (data == null) {
      throw const DeleteAccountException(DeleteAccountFailure.server);
    }
    if (data['ok'] != true) {
      throw DeleteAccountException(_mapError(data['error'] as String?));
    }
  }

  /// Translates the Edge Function's HTTP status into a trader-safe failure.
  static DeleteAccountFailure _classify(int statusCode) {
    switch (statusCode) {
      case 401:
        return DeleteAccountFailure.unauthorized;
      case 403:
        return DeleteAccountFailure.forbidden;
      case 405:
        return DeleteAccountFailure.server;
      case 503:
        return DeleteAccountFailure.notConfigured;
      case 429:
        return DeleteAccountFailure.unavailable;
      case 500:
        return DeleteAccountFailure.server;
      default:
        return DeleteAccountFailure.unreachable;
    }
  }

  /// Maps the function's own short error token (mirrors `classifyStatus` in `shared.ts`) onto
  /// trader-safe copy. An unknown token still never leaks raw text — it falls back to [server].
  static DeleteAccountFailure _mapError(String? error) {
    switch (error) {
      case 'Unauthorized':
        return DeleteAccountFailure.unauthorized;
      case 'Method not allowed':
        return DeleteAccountFailure.server;
      case 'notConfigured':
        return DeleteAccountFailure.notConfigured;
      case 'server':
        return DeleteAccountFailure.server;
      default:
        return DeleteAccountFailure.server;
    }
  }
}
