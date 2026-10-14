import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tradeguard/core/services/supabase_service.dart';

/// Trader-safe failure type.
///
/// Raw Supabase and platform errors are never surfaced to the UI. They are mapped
/// onto this type so the display layer can show neutral, actionable copy and
/// never leak backend internals.
class PurchaseFailure implements Exception {
  final String message;

  const PurchaseFailure(this.message);

  @override
  String toString() => 'PurchaseFailure: $message';
}

/// Abstraction over the premium ("Pro") status check.
///
/// Premium is a single boolean on the user's `profiles` row (`is_premium`),
/// flipped to true by the `flutterwave-webhook` Edge Function after a Flutterwave
/// `charge.completed` (or `subscription.created`). There is no store SDK and no subscription table: the app
/// opens a Flutterwave Payment Link in the browser, then re-reads this flag.
abstract class PurchaseRepository {
  /// The trader's current premium status, read from `profiles.is_premium`.
  Future<bool> isPro();

  /// A stream of the current premium status. Emits the present value once; the
  /// paywall's "Check Status" action re-reads via the notifier rather than
  /// relying on a push, so this stays a simple one-shot stream.
  Stream<bool> watchProStatus();
}

/// Live Supabase implementation: reads `profiles.is_premium` for the signed-in
/// trader. RLS (migration 0012) allows a user to SELECT only their own row, so
/// the read is inherently own-row scoped; the explicit `id` filter simply makes
/// that intent local and mirrors the other own-row repositories.
class SupabasePurchaseRepository implements PurchaseRepository {
  SupabasePurchaseRepository([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  SupabaseClient get _client => _service.client;

  @override
  Future<bool> isPro() async {
    final String? userId = _client.auth.currentUser?.id;
    // Without a session there is no row to read; a signed-out trader is not Pro.
    if (userId == null || userId.isEmpty) return false;
    try {
      final List<Map<String, dynamic>> rows = await (_client
          .from('profiles')
          .select('is_premium')
          .eq('id', userId)
          .limit(1))
          .timeout(SupabaseService.networkTimeout);
      if (rows.isEmpty) return false;
      return rows.first['is_premium'] == true;
    } catch (_) {
      // A network/backend failure must never read as "premium"; treat it as not
      // Pro and let the notifier surface a retry, never a raw error string.
      return false;
    }
  }

  @override
  Stream<bool> watchProStatus() => Stream<bool>.fromFuture(isPro());
}


/// In-memory purchase repository used by mock mode and tests.
///
/// Defaults to "not pro" and exposes a test hook ([setProStatus]) to flip the
/// pro status. [isPro] and [watchProStatus] both reflect the current value.
class MockPurchaseRepository implements PurchaseRepository {
  MockPurchaseRepository([bool isPro = false]) : _isPro = isPro;

  bool _isPro;
  final _controller = StreamController<bool>.broadcast();

  /// Test hook: flip the pro status that [watchProStatus] emits.
  void setProStatus(bool value) {
    _isPro = value;
    _controller.add(value);
  }

  @override
  Future<bool> isPro() async => _isPro;

  @override
  Stream<bool> watchProStatus() {
    // Single-subscription controller so the current status is buffered and
    // delivered to the first listener even though it subscribes after add().
    final controller = StreamController<bool>()..add(_isPro);
    _controller.stream.listen((value) {
      if (!controller.isClosed) controller.add(value);
    });
    return controller.stream;
  }
}
