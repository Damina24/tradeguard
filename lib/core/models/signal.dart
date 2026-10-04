enum SignalDirection { buy, sell }

enum SignalStatus { active, closed, cancelled }

class Signal {
  const Signal({
    required this.id,
    required this.pair,
    required this.direction,
    required this.entry,
    required this.stop,
    required this.tp1,
    required this.confidence,
    required this.rationale,
    required this.createdAt,
    this.tp2,
    this.tp3,
    this.status = SignalStatus.active,
    this.resultPips,
    this.premium = false,
  });

  final String id;
  final String pair;
  final SignalDirection direction;
  final double entry;
  final double stop;
  final double tp1;
  final double? tp2;
  final double? tp3;
  final int confidence;
  final String rationale;
  final DateTime createdAt;
  final SignalStatus status;
  final double? resultPips;
  final bool premium;

  factory Signal.fromJson(Map<String, dynamic> json) => Signal(
        id: json['id'] as String,
        pair: json['pair'] as String,
        direction: json['direction'] == 'sell'
            ? SignalDirection.sell
            : SignalDirection.buy,
        entry: (json['entry'] as num).toDouble(),
        stop: (json['sl'] as num).toDouble(),
        tp1: (json['tp1'] as num).toDouble(),
        tp2: (json['tp2'] as num?)?.toDouble(),
        tp3: (json['tp3'] as num?)?.toDouble(),
        confidence: json['confidence'] as int? ?? 60,
        rationale: json['rationale'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
                DateTime.now(),
        status: SignalStatus.values.firstWhere(
          (SignalStatus s) => s.name == (json['status'] ?? 'active'),
          orElse: () => SignalStatus.active,
        ),
        resultPips: (json['result_pips'] as num?)?.toDouble(),
        premium: json['premium'] as bool? ?? false,
      );
}
