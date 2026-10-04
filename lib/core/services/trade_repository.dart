import '../models/trade.dart';
import 'mock_data.dart';

/// Sort floor for the rare trade that has neither a close nor an open time.
final DateTime _sortFloor = DateTime.fromMillisecondsSinceEpoch(0);

abstract class TradeRepository {
  /// Most recent trades first. [accountId] filters to a single broker account.
  Future<List<Trade>> fetchTrades({String? accountId, int limit = 200});

  Future<void> updateGrade(String tradeId, String grade);

  Future<void> updateNotes(String tradeId, String notes);
}

/// In-memory journal used in mock mode, seeded with the same deterministic data the tests use.
class MockTradeRepository implements TradeRepository {
  MockTradeRepository() : _trades = MockData.trades();

  final List<Trade> _trades;

  @override
  Future<List<Trade>> fetchTrades({String? accountId, int limit = 200}) async {
    final List<Trade> rows = _trades
        .where((Trade t) => accountId == null || t.accountId == accountId)
        .toList()
      ..sort(
        (Trade a, Trade b) =>
            (b.closeTime ?? b.openTime ?? _sortFloor)
                .compareTo(a.closeTime ?? a.openTime ?? _sortFloor),
      );
    return List<Trade>.unmodifiable(rows.take(limit));
  }

  @override
  Future<void> updateGrade(String tradeId, String grade) async {
    _replace(tradeId, (Trade t) => t.copyWith(grade: grade));
  }

  @override
  Future<void> updateNotes(String tradeId, String notes) async {
    _replace(tradeId, (Trade t) => t.copyWith(notes: notes));
  }

  void _replace(String tradeId, Trade Function(Trade) transform) {
    final int i = _trades.indexWhere((Trade t) => t.id == tradeId);
    if (i < 0) throw StateError('Unknown trade: $tradeId');
    _trades[i] = transform(_trades[i]);
  }
}
