import '../../../core/models/chart_analysis.dart';
import 'chart_analysis_repository.dart';

/// Offline deterministic analysis for mock mode.
class MockChartAnalysisRepository
    implements ChartAnalysisRepository {
  MockChartAnalysisRepository({
    this.latency = const Duration(milliseconds: 400),
  });

  final Duration latency;

  String? Function(String imageUrl)? chartsLookup;

  static ChartAnalysis buildFor(String imageUrl) {
    return ChartAnalysis(
      bias: ChartAnalysisBias.neutral,
      levels: const <double>[],
      entry: null,
      sl: null,
      tp: const <double>[],
      note: 'Demo analysis of $imageUrl. No market data was read.',
    );
  }

  @override
  bool get isStubbed => true;

  @override
  Future<ChartAnalysis?> fetchAnalysis() async {
    await Future<void>.delayed(latency);
    return null;
  }

  @override
  Future<ChartAnalysis> requestAnalysis(String imageUrl) async {
    await Future<void>.delayed(latency);
    final String? chart = chartsLookup?.call(imageUrl);
    if (chart == null) {
      throw const ChartAnalysisException(
        ChartAnalysisFailure.invalidImage,
      );
    }
    return buildFor(imageUrl);
  }
}
