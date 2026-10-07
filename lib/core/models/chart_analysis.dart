import 'package:collection/collection.dart';

/// One analysed chart: the ai-analyze-chart output as plain data.
///
/// Caps mirror shared.ts: levels 6, tp 3, note 400 chars.
class ChartAnalysis {
  ChartAnalysis({
    required this.bias,
    required List<double> levels,
    required this.entry,
    required this.sl,
    required List<double> tp,
    required String note,
  })  : levels = List<double>.unmodifiable(levels.take(6)),
        tp = List<double>.unmodifiable(tp.take(3)),
        note = _clip(note);

  final ChartAnalysisBias bias;
  final List<double> levels;
  final double? entry;
  final double? sl;
  final List<double> tp;
  final String note;

  static String _clip(String v) {
    final String c = v.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (c.length <= 400) return c;
    return c.substring(0, 400);
  }

  static const ListEquality<double> _eq = ListEquality<double>();

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ChartAnalysis &&
        bias == other.bias &&
        _eq.equals(levels, other.levels) &&
        entry == other.entry &&
        sl == other.sl &&
        _eq.equals(tp, other.tp) &&
        note == other.note;
  }

  @override
  int get hashCode => Object.hash(
        bias,
        Object.hashAll(levels),
        entry,
        sl,
        Object.hashAll(tp),
        note,
      );

  factory ChartAnalysis.fromJson(Map<String, dynamic> j) {
    return ChartAnalysis(
      bias: ChartAnalysisBias.fromName(j['bias'] as String?),
      levels: _dbl(j['levels']),
      entry: (j['entry'] as num?)?.toDouble(),
      sl: (j['sl'] as num?)?.toDouble(),
      tp: _dbl(j['tp']),
      note: j['note'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'bias': bias.name,
        'levels': levels,
        'entry': entry,
        'sl': sl,
        'tp': tp,
        'note': note,
      };

  static List<double> _dbl(Object? raw) {
    if (raw is! List) return const <double>[];
    final List<double> out = <double>[];
    for (final Object? e in raw) {
      if (e is num && e.isFinite) out.add(e.toDouble());
    }
    return out;
  }
}

/// Model bias. Unknown strings fall back to neutral.
enum ChartAnalysisBias {
  bullish('Bullish', 'Structure leans up.'),
  bearish('Bearish', 'Structure leans down.'),
  neutral('Neutral', 'No clear direction.');

  const ChartAnalysisBias(this.label, this.desc);

  final String label;
  final String desc;

  static ChartAnalysisBias fromName(String? n) {
    return ChartAnalysisBias.values.firstWhere(
      (ChartAnalysisBias e) => e.name == n,
      orElse: () => ChartAnalysisBias.neutral,
    );
  }
}
