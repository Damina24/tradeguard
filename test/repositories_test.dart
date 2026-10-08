import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/account.dart';
import 'package:tradeguard/core/models/trade.dart';
import 'package:tradeguard/core/services/account_repository.dart';
import 'package:tradeguard/core/services/auth_repository.dart';
import 'package:tradeguard/core/services/providers.dart';
import 'package:tradeguard/core/services/services.dart';
import 'package:tradeguard/core/services/trade_repository.dart';
import 'package:tradeguard/features/journal/data/trade_screenshot_service.dart';

void main() {
  group('MockAccountRepository', () {
    test('seeds the demo prop accounts', () async {
      final MockAccountRepository repo = MockAccountRepository();
      final accounts = await repo.fetchAccounts();
      expect(accounts.length, 2);
      expect(accounts.first.nickname, 'FTMO EVAL 100K');
      expect(accounts.last.nickname, 'FUNDED 50K');
    });

    test('fetchAccounts returns an unmodifiable view', () async {
      final MockAccountRepository repo = MockAccountRepository();
      final accounts = await repo.fetchAccounts();
      expect(
        () => accounts.add(accounts.first),
        throwsUnsupportedError,
      );
    });

    test('snapshot mirrors the account numbers', () async {
      final MockAccountRepository repo = MockAccountRepository();
      final accounts = await repo.fetchAccounts();
      final snap = await repo.fetchSnapshot(accounts.first.id);
      expect(snap.equity, accounts.first.equity);
      expect(snap.dailyPnl, accounts.first.dailyPnl);
      expect(snap.balance, accounts.first.balance);
    });

    test('snapshot falls back to initial balance when peak is unset',
        () async {
      final MockAccountRepository repo = MockAccountRepository();
      final accounts = await repo.fetchAccounts();
      final AccountSnapshot snap = AccountSnapshot.fromAccount(
        accounts.first,
        now: DateTime(2026),
      );
      expect(snap.peakEquity, accounts.first.peakEquity);
      expect(snap.asOf, DateTime(2026));
    });

    test('fetchSnapshot rejects an unknown account', () async {
      final MockAccountRepository repo = MockAccountRepository();
      await expectLater(repo.fetchSnapshot('nope'), throwsStateError);
    });

    test('create then delete round-trips', () async {
      final MockAccountRepository repo = MockAccountRepository();
      final accounts = await repo.fetchAccounts();
      final extra = accounts.first;
      await repo.createAccount(_withId(extra, 'acc_new'));
      expect((await repo.fetchAccounts()).length, 3);

      await repo.deleteAccount('acc_new');
      final after = await repo.fetchAccounts();
      expect(after.length, 2);
      expect(after.any((a) => a.id == 'acc_new'), isFalse);
    });

    test('setEquityGuardEnabled updates and persists', () async {
      final MockAccountRepository repo = MockAccountRepository();
      await repo.setEquityGuardEnabled('acc_eval_100k', true);
      final accounts = await repo.fetchAccounts();
      expect(
        accounts.firstWhere((a) => a.id == 'acc_eval_100k').equityGuardEnabled,
        isTrue,
      );
      await expectLater(
        repo.setEquityGuardEnabled('nope', true),
        throwsStateError,
      );
    });
  });

  group('MockTradeRepository', () {
    test('returns the newest trade first', () async {
      final MockTradeRepository repo = MockTradeRepository();
      final trades = await repo.fetchTrades();
      expect(trades.isNotEmpty, isTrue);
      expect(trades.first.id, 't_0');
    });

    test('filters by account', () async {
      final MockTradeRepository repo = MockTradeRepository();
      final trades = await repo.fetchTrades(accountId: 'acc_eval_100k');
      expect(
        trades.every((t) => t.accountId == 'acc_eval_100k'),
        isTrue,
      );
      expect(trades.length, 30);
    });

    test('honours the limit', () async {
      final MockTradeRepository repo = MockTradeRepository();
      expect((await repo.fetchTrades(limit: 5)).length, 5);
    });

    test('updateGrade persists across re-reads', () async {
      final MockTradeRepository repo = MockTradeRepository();
      await repo.updateGrade('t_3', 'A');
      final trade = (await repo.fetchTrades())
          .firstWhere((t) => t.id == 't_3');
      expect(trade.grade, 'A');
    });

    test('updateNotes persists and leaves money fields alone', () async {
      final MockTradeRepository repo = MockTradeRepository();
      final before = (await repo.fetchTrades()).firstWhere((t) => t.id == 't_3');
      await repo.updateNotes('t_3', 'waited for retest');
      final after = (await repo.fetchTrades()).firstWhere((t) => t.id == 't_3');
      expect(after.notes, 'waited for retest');
      expect(after.pnl, before.pnl);
      expect(after.lots, before.lots);
    });

    test('updateScreenshot links the storage path', () async {
      final MockTradeRepository repo = MockTradeRepository();
      await repo.updateScreenshot('t_3', 'uid/t_3/123.png');
      final Trade trade =
          (await repo.fetchTrades()).firstWhere((Trade t) => t.id == 't_3');
      expect(trade.screenshotUrl, 'uid/t_3/123.png');
    });

    test('uploadScreenshot uploads then links the returned path', () async {
      final MockTradeScreenshotService screenshots =
          MockTradeScreenshotService();
      final TradesNotifier notifier = TradesNotifier(
        MockTradeRepository(),
        screenshots: screenshots,
      );
      await notifier.refresh();
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      await notifier.uploadScreenshot(
        't_3',
        PickedScreenshot(
          bytes: bytes,
          fileName: 'chart.png',
          mimeType: 'image/png',
        ),
      );
      final Trade linked =
          notifier.state.firstWhere((Trade t) => t.id == 't_3');
      expect(linked.screenshotUrl, isNotNull);
      expect(await screenshots.download(linked.screenshotUrl), bytes);
      notifier.dispose();
    });

    test('screenshot providers resolve the mock service by default', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(tradeScreenshotServiceProvider),
        same(Services.instance.screenshots),
      );
      expect(
        container.read(tradeScreenshotServiceProvider),
        isA<MockTradeScreenshotService>(),
      );
    });

    test('unknown trade throws', () async {
      final MockTradeRepository repo = MockTradeRepository();
      await expectLater(repo.updateGrade('nope', 'A'), throwsStateError);
    });
  });

  group('Services locator', () {
    test('resolves mocks when SUPABASE_URL is empty', () {
      expect(Services.instance.isMock, isTrue);
      expect(Services.instance.auth, isA<MockAuthRepository>());
      expect(Services.instance.accounts, isA<MockAccountRepository>());
      expect(Services.instance.trades, isA<MockTradeRepository>());
    });
  });
}

/// Copy of [a] with a different id, used to exercise create/delete.
TradingAccount _withId(TradingAccount a, String id) => TradingAccount(
      id: id,
      nickname: a.nickname,
      platform: a.platform,
      phase: a.phase,
      currency: a.currency,
      initialBalance: a.initialBalance,
      profitTarget: a.profitTarget,
      dailyLossLimit: a.dailyLossLimit,
      maxDrawdown: a.maxDrawdown,
      drawdownType: a.drawdownType,
      equity: a.equity,
      balance: a.balance,
      dailyPnl: a.dailyPnl,
      peakEquity: a.peakEquity,
      propFirm: a.propFirm,
      metaapiAccountId: a.metaapiAccountId,
      equityGuardEnabled: a.equityGuardEnabled,
    );
