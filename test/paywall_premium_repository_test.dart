import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/core/services/services.dart';
import 'package:tradeguard/features/paywall/data/purchase_repository.dart';

/// Premium is a single boolean on `profiles.is_premium`, read through
/// [PurchaseRepository]. These tests pin the in-memory repository and the
/// provider wiring (the Supabase read itself needs a live project and is
/// covered by the Edge Function + migration). The live Supabase repository is
/// only constructed when a backend is configured, so in this test environment
/// the default is the mock.
void main() {
  group('MockPurchaseRepository', () {
    test('defaults to not-premium', () async {
      final repo = MockPurchaseRepository();
      expect(await repo.isPro(), isFalse);
    });

    test('the pro hook flips the status and the stream', () async {
      final repo = MockPurchaseRepository();
      expect(await repo.isPro(), isFalse);

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

  group('provider wiring', () {
    test('default provider resolves to the mock repository', () async {
      // This environment has no SUPABASE_URL, so Services is in mock mode and
      // its premium repository is the in-memory mock.
      expect(Services.instance.purchases, isA<MockPurchaseRepository>());
      expect(await Services.instance.purchases.isPro(), isFalse);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(purchasesProvider.notifier);
      // Let the notifier's async refresh() settle while the container is alive,
      // so it never writes state after dispose.
      await Future<void>.delayed(Duration.zero);
      expect(notifier, isA<PurchaseNotifier>());
      expect(container.read(purchasesProvider).isPro, isFalse);
    });

    test('refresh reads the premium flag into state', () async {
      final repo = MockPurchaseRepository();
      final container = ProviderContainer(
        overrides: <Override>[
          purchasesProvider.overrideWith((Ref ref) => PurchaseNotifier(repo)),
        ],
      );
      addTearDown(container.dispose);

      // Initial read settles to not-premium.
      await Future<void>.delayed(Duration.zero);
      expect(container.read(purchasesProvider).isPro, isFalse);

      // Flip the flag and re-read via the notifier's refresh().
      repo.setProStatus(true);
      await container.read(purchasesProvider.notifier).refresh();
      expect(container.read(purchasesProvider).isPro, isTrue);
    });
  });
}
