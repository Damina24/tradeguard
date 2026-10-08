import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/core/services/services.dart';
import 'package:tradeguard/features/paywall/data/purchase_repository.dart';

void main() {
  group('MockPurchaseRepository', () {
    test('defaults to not-pro', () async {
      final repo = MockPurchaseRepository();
      expect(await repo.isPro(), isFalse);
      expect(await repo.loadPackages(), isEmpty);
    });

    test('pro hook flips the status and the stream', () async {
      final repo = MockPurchaseRepository();
      expect(await repo.isPro(), isFalse);

      // The stream created after the flip emits the new status.
      repo.setProStatus(true);
      expect(await repo.isPro(), isTrue);
      expect(await repo.watchProStatus().first, isTrue);
    });

    test('watchProStatus emits the current value to a new listener', () async {
      final repo = MockPurchaseRepository();
      expect(await repo.watchProStatus().first, isFalse);

      repo.setProStatus(true);
      expect(await repo.watchProStatus().first, isTrue);
    });
  });

  group('RevenueCatPurchaseRepository (unconfigured)', () {
    test('isConfigured is false when no keys are set', () {
      final repo = RevenueCatPurchaseRepository();
      expect(repo.isConfigured, isFalse);
    });

    test('isPro returns false without throwing', () async {
      final repo = RevenueCatPurchaseRepository();
      expect(await repo.isPro(), isFalse);
    });

    test('loadPackages returns an empty list without throwing', () async {
      final repo = RevenueCatPurchaseRepository();
      expect(await repo.loadPackages(), isEmpty);
    });

    test('watchProStatus emits false exactly once without throwing', () async {
      final repo = RevenueCatPurchaseRepository();
      expect(await repo.watchProStatus().first, isFalse);
    });
  });

  group('provider wiring', () {
    test('default provider resolves to the mock repository', () async {
      // This environment has no SUPABASE_URL, so Services is in mock mode and
      // its purchase repository is the in-memory mock.
      expect(Services.instance.purchases, isA<MockPurchaseRepository>());
      expect(await Services.instance.purchases.isPro(), isFalse);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(purchasesProvider.notifier);
      // Let the notifier's async _sync() settle while the container is alive,
      // so it never writes state after dispose.
      await Future<void>.delayed(Duration.zero);
      expect(notifier, isA<PurchaseNotifier>());
      expect(container.read(purchasesProvider).isPro, isFalse);
    });
  });
}
