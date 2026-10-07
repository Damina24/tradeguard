import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/core/models/chart_analysis.dart';
import 'package:tradeguard/features/chart_analysis/data/chart_analysis_repository.dart';
import 'package:tradeguard/features/chart_analysis/data/mock_chart_analysis_repository.dart';

void main() {
  group('MockChartAnalysisRepository', () {
    test('isStubbed is true', () {
      expect(MockChartAnalysisRepository().isStubbed, isTrue);
    });

    test('deterministic for same chart', () async {
      final MockChartAnalysisRepository r =
          MockChartAnalysisRepository(
        latency: Duration.zero,
      );
      r.chartsLookup = (_) => 'chart';
      final ChartAnalysis a =
          await r.requestAnalysis('chart.png');
      final ChartAnalysis b =
          await r.requestAnalysis('chart.png');
      expect(a, equals(b));
    });

    test('no lookup throws', () {
      final MockChartAnalysisRepository r =
          MockChartAnalysisRepository(
        latency: Duration.zero,
      );
      expect(
        r.requestAnalysis('chart.png'),
        throwsA(isA<ChartAnalysisException>()),
      );
    });

    test('buildFor is neutral and risk free', () {
      final ChartAnalysis x =
          MockChartAnalysisRepository.buildFor('c');
      expect(x.bias, ChartAnalysisBias.neutral);
      expect(x.levels, isEmpty);
      expect(x.entry, isNull);
      expect(x.sl, isNull);
      expect(x.tp, isEmpty);
    });
  });
}
