import 'package:tradeguard/core/utils/trading_math.dart';

import '../domain/copy_signal.dart';
import 'copy_signal_repository.dart';

/// Deterministic, offline stub for the `copy-signal` edge function.
///
/// No network, no MetaAPI, no server equity: every answer comes from the same
/// seed the mock accounts are created with (`MockData.accounts()`), so the
/// sheet can be fully exercised with no backend and nothing pretends to be a
/// live broker round.
///
/// It only ever implements the PAPER contract: paper rows are simulated fills
/// with `simulated: true`, and this stub never contacts a broker. `mode` is
/// accepted for interface compatibility with the Supabase implementation —
/// the confirm sheet always sends `mode='paper'`.
class MockCopySignalRepository implements CopySignalRepository {
  MockCopySignalRepository({Map<String, double>? accountEquity})
    : _equity = _seedEquity(accountEquity);

  final Map<String, double> _equity;

  static Map<String, double> _seedEquity(Map<String, double>? overrides) {
    final Map<String, double> equity = <String, double>{
      'acc_eval_100k': 103450,
      'acc_funded_50k': 51820,
    };
    if (overrides != null) equity.addAll(overrides);
    return equity;
  }

  @override
  bool get isStubbed => true;

  @override
  Future<CopySignalResult> placeCopySignal({
    required String signalId,
    required List<String> accountIds,
    required String signalPair,
    required double stopPips,
    required double riskPct,
    required String mode,
  }) {
    final List<CopySignalRow> results = <CopySignalRow>[];
    for (final String accountId in accountIds) {
      final double lots = TradingMath.lotSize(
        balance: _equity[accountId]!,
        riskPct: riskPct,
        symbol: signalPair,
        stopPips: stopPips,
      );
      results.add(
        CopySignalRow(
          accountId: accountId,
          mode: 'paper',
          lots: lots,
          riskPct: riskPct,
          status: 'placed',
          simulated: true,
        ),
      );
    }
    return Future.value(
      CopySignalResult(ok: true, mode: 'paper', results: results),
    );
  }
}
