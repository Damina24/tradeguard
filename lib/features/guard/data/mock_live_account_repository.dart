import '../../../core/models/live_account.dart';
import 'live_account_repository.dart';

/// Offline live-data source, so the Guard dashboard's live section is fully
/// exercisable with no backend and no MetaAPI credentials — the same reason
/// every other repository has a mock half.
///
/// The numbers mirror `MockData`'s accounts so the live section and the guard
/// cards can never disagree in demo mode. It is labelled CONNECTED because that
/// is the state the UI is being verified against; a live read that fails maps to
/// `offline` in the Supabase half, never here.
class MockLiveAccountRepository implements LiveAccountRepository {
  const MockLiveAccountRepository();

  @override
  Future<LiveAccountData> fetchLive(String accountId) async {
    // A touch of latency so the loading shimmer is actually visible in a demo.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return LiveAccountData(
      accountId: accountId,
      balance: 103450,
      equity: 103712.40,
      connection: BrokerConnectionState.connected,
      linked: true,
      asOf: DateTime.now(),
      positions: const <OpenPosition>[
        OpenPosition(
          id: 'pos-1',
          symbol: 'XAUUSD',
          isBuy: true,
          lots: 0.50,
          openPrice: 2345.10,
          currentPrice: 2351.40,
          pnl: 312.00,
        ),
        OpenPosition(
          id: 'pos-2',
          symbol: 'EURUSD',
          isBuy: false,
          lots: 1.00,
          openPrice: 1.0850,
          currentPrice: 1.0810,
          pnl: -40.00,
        ),
      ],
    );
  }
}
