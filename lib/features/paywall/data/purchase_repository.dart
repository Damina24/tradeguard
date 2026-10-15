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
/// Premium is `is_premium` on the user's `profiles` row PLUS a non-expired
/// `premium_expires_at` (migration 0013): `is_premium == true AND
/// (premium_expires_at IS NULL OR premium_expires_at > NOW())`. A NULL expiry
/// is a legacy/lifetime grant predating 0013; the `flutterwave-webhook` Edge
/// Function always writes a concrete expiry for new grants, so the "one monthly
/// payment unlocks Pro forever" loophole is closed. There is no store SDK and
/// no subscription table: the app opens a Flutterwave Payment Link in the
/// browser, then re-reads this entitlement.
abstract class PurchaseRepository {
  /// The trader's current premium status: the flag AND the expiry.
  Future<bool> isPro();

  /// A stream of the current premium status. Emits the present value once; the
  /// paywall's "Check Status" action re-reads via the notifier rather than
  /// relying on a push, so this stays a simple one-shot stream.
  Stream<bool> watchProStatus();
}

/// Live Supabase implementation: reads `profiles.is_premium` +
/// `profiles.premium_expires_at` for the signed-in trader. RLS (migration
/// 0012) allows a user to SELECT only their own row, so the read is inherently
/// own-row scoped; the explicit `id` filter simply makes that intent local and
/// mirrors the other own-row repositories.
class SupabasePurchaseRepository implements PurchaseRepository {
  SupabasePurchaseRepository([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  SupabaseClient get _client => _service.client;

  /// Pure entitlement rule (mirrors the SQL in migration 0013's comment), kept
  /// static so it is unit-testable without a Supabase project.
  static bool isEntitled({required bool flag, DateTime? expiresAt, DateTime? now}) {
    if (!flag) return false;
    if (expiresAt == null) return true; // legacy/lifetime grant
    return expiresAt.isAfter(now ?? DateTime.now().toUtc());
  }

  @override
  Future<bool> isPro() async {
    final String? userId = _client.auth.currentUser?.id;
    // Without a session there is no row to read; a signed-out trader is not Pro.
    if (userId == null || userId.isEmpty) return false;
    try {
      final List<Map<String, dynamic>> rows = await (_client
          .from('profiles')
          .select('is_premium, premium_expires_at')
          .eq('id', userId)
          .limit(1))
          .timeout(SupabaseService.networkTimeout);
      if (rows.isEmpty) return false;
      final Map<String, dynamic> row = rows.first;
      final bool flag = row['is_premium'] == true;
      DateTime? expiresAt;
      final Object? raw = row['premium_expires_at'];
      if (raw is String && raw.isNotEmpty) {
        expiresAt = DateTime.tryParse(raw)?.toUtc();
      }
      return isEntitled(flag: flag, expiresAt: expiresAt);
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
/// Defaults to "not pro" and exposes test hooks ([setProStatus] / [setExpiry])
/// to flip the entitlement. [isPro] honours the same rule as
/// [SupabasePurchaseRepository.isEntitled]: the flag AND a non-expired
/// `premium_expires_at` (NULL = lifetime).
class MockPurchaseRepository implements PurchaseRepository {
  MockPurchaseRepository([bool isPro = false]) : _isPro = isPro;

  bool _isPro;
  DateTime? _expiresAt;
  final _controller = StreamController<bool>.broadcast();

  /// Test hook: flip the pro status that [watchProStatus] emits.
  void setProStatus(bool value) {
    _isPro = value;
    _controller.add(isProSync);
  }

  /// Test hook: set the expiry honoured by [isProSync]/[isPro].
  void setExpiry(DateTime? value) {
    _expiresAt = value?.toUtc();
    _controller.add(isProSync);
  }

  /// Synchronous form of the entitlement rule (used by the stream above).
  bool get isProSync => SupabasePurchaseRepository.isEntitled(
        flag: _isPro,
        expiresAt: _expiresAt,
      );

  @override
  Future<bool> isPro() async => isProSync;

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
