import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/chart_analysis.dart';

void main() {
  group('ChartAnalysis', () {
    test('equal analyses compare equal', () {
      ChartAnalysis a() => ChartAnalysis(
            bias: ChartAnalysisBias.neutral,
            levels: const <double>[100.0],
            entry: 100.5,
            sl: null,
            tp: const <double>[102.0],
            note: 'Test note',
          );
      expect(a(), equals(a()));
    });

    test('tp capped at 3, levels at 6', () {
      final ChartAnalysis x = ChartAnalysis(
        bias: ChartAnalysisBias.neutral,
        levels: const <double>[1, 2, 3, 4, 5, 6, 7, 8],
        entry: null,
        sl: null,
        tp: const <double>[1, 2, 3, 4],
        note: '',
      );
      expect(x.levels, hasLength(6));
      expect(x.tp, hasLength(3));
    });

    test('note clipped at 400 with no newline', () {
      final String long = List<String>.filled(500, 'x').join();
      final ChartAnalysis x = ChartAnalysis(
        bias: ChartAnalysisBias.neutral,
        levels: const <double>[],
        entry: null,
        sl: null,
        tp: const <double>[],
        note: long,
      );
      expect(x.note.length, lessThanOrEqualTo(400));
      expect(x.note.contains('\n'), isFalse);
    });

    test('json round trip', () {
      final ChartAnalysis o = ChartAnalysis(
        bias: ChartAnalysisBias.bearish,
        levels: const <double>[100.0],
        entry: 99.5,
        sl: 101.0,
        tp: const <double>[98.0],
        note: 'Round trip',
      );
      expect(ChartAnalysis.fromJson(o.toJson()), equals(o));
    });

    test('bias fromName falls back to neutral', () {
      expect(
        ChartAnalysisBias.fromName('nope'),
        ChartAnalysisBias.neutral,
      );
    });
  });
}
