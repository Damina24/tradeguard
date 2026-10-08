import 'dart:async';

import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:tradeguard/core/services/supabase_service.dart';

import 'revenuecat_config.dart';

/// Trader-safe failure type.
///
/// Raw SDK and platform errors are never surfaced to the UI. They are mapped
/// onto this type so the display layer can show neutral, actionable copy and
/// never leak SDK internals.
class PurchaseFailure implements Exception {
  final String message;

  const PurchaseFailure(this.message);

  @override
  String toString() => 'PurchaseFailure: $message';
}

/// Abstraction over the store purchase path.
///
/// Live repositories are only "configured" when a platform key exists, so an
/// unconfigured build degrades to offline behaviour without throwing.
abstract class PurchaseRepository {
  Future<bool> isPro();
  Stream<bool> watchProStatus();
  Future<List<Object>> loadPackages();
  Future<void> purchase(Object package);
  Future<void> restore();
}

/// Live RevenueCat implementation.
///
/// Configuration happens in the constructor. If the current platform's key is
/// missing, every method degrades to the offline behaviour (see [isPro],
/// [watchProStatus], [loadPackages]).
class RevenueCatPurchaseRepository implements PurchaseRepository {
  RevenueCatPurchaseRepository() {
    unawaited(_init());
  }

  bool _isConfigured = false;

  /// True once [Purchases.configure] has completed successfully for a build
  /// that has a platform key.
  bool get isConfigured => _isConfigured;

  @override
  Future<bool> isPro() async {
    if (!_isConfigured) return false;
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return _hasEntitlement(customerInfo);
    } on Exception catch (e) {
      throw PurchaseFailure(_traderMessage(e));
    }
  }

  @override
  Stream<bool> watchProStatus() {
    if (!_isConfigured) {
      // Unconfigured builds are never Pro: emit false exactly once, then end.
      return Stream<bool>.value(false);
    }
    _ensureSubscription();
    return _statusController.stream;
  }

  @override
  Future<List<Object>> loadPackages() async {
    if (!_isConfigured) return const <Object>[];
    try {
      final offerings = await Purchases.getOfferings();
      final packages = <Object>[];
      for (final offering in offerings.all.values) {
        packages.addAll(offering.availablePackages);
      }
      return packages;
    } on Exception catch (e) {
      throw PurchaseFailure(_traderMessage(e));
    }
  }

  @override
  Future<void> purchase(Object package) async {
    if (!_isConfigured) {
      throw const PurchaseFailure(
        'Purchases are not configured for this build.',
      );
    }
    try {
      await Purchases.purchasePackage(package as Package);
    } on Exception catch (e) {
      throw PurchaseFailure(_traderMessage(e));
    }
  }

  @override
  Future<void> restore() async {
    if (!_isConfigured) {
      throw const PurchaseFailure(
        'Purchases are not configured for this build.',
      );
    }
    try {
      await Purchases.restorePurchases();
    } on Exception catch (e) {
      throw PurchaseFailure(_traderMessage(e));
    }
  }

  Future<void> _init() async {
    if (!RevenueCatConfig.isConfigured) {
      _isConfigured = false;
      return;
    }
    try {
      final config = PurchasesConfiguration(RevenueCatConfig.platformKey);
      final uid = await _currentAuthUid();
      if (uid != null && uid.isNotEmpty) {
        config.appUserID = uid;
      }
      await Purchases.configure(config);
      _isConfigured = true;
    } catch (_) {
      _isConfigured = false;
    }
  }

  Future<String?> _currentAuthUid() async {
    try {
      return SupabaseService.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  bool _hasEntitlement(CustomerInfo customerInfo) =>
      customerInfo.entitlements.all
          .containsKey(RevenueCatConfig.entitlementId);

  String _traderMessage(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('canceled') || raw.contains('cancelled')) {
      return 'Purchase cancelled. Please try again.';
    }
    if (raw.contains('network') || raw.contains('connection')) {
      return 'Could not reach the store. Check your connection and try again.';
    }
    return 'Something went wrong with the purchase. Please try again.';
  }

  final _statusController = StreamController<bool>.broadcast();
  bool _subscriptionRegistered = false;

  void _ensureSubscription() {
    if (_subscriptionRegistered) return;
    _subscriptionRegistered = true;
    Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdate);
  }

  void _onCustomerInfoUpdate(CustomerInfo customerInfo) {
    if (!_statusController.isClosed) {
      _statusController.add(_hasEntitlement(customerInfo));
    }
  }
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

  @override
  Future<List<Object>> loadPackages() async => const <Object>[];

  @override
  Future<void> purchase(Object package) async {
    // Mock: no-op.
  }

  @override
  Future<void> restore() async {
    // Mock: no-op.
  }
}
