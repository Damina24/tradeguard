import '../../../core/models/chart_analysis.dart';

/// Access to chart analysis: live Edge Function or offline mock.
///
/// No caller may choose whose analysis to read. There is no userId
/// parameter. Identity comes from the session inside the impl, and
/// the function re-derives it from the verified JWT.
abstract class ChartAnalysisRepository {
  bool get isStubbed;
  Future<ChartAnalysis?> fetchAnalysis();
  Future<ChartAnalysis> requestAnalysis(String imageUrl);
}

/// Why an analysis could not be produced.
enum ChartAnalysisFailure {
  notConfigured('AI analysis is not available yet.'),
  unauthorized('Sign in to analyse charts.'),
  forbidden('That chart is not available.'),
  unreachable('Could not reach the analysis service.'),
  failed('The analysis could not be completed.'),
  invalidImage('The image could not be analysed.'),
  unavailable('The chart is not available yet.'),
  malformed('The analysis came back unparseable.');

  const ChartAnalysisFailure(this.message);

  final String message;
}

/// A failed request. Carries a failure, never a raw message.
class ChartAnalysisException implements Exception {
  const ChartAnalysisException(this.failure);

  final ChartAnalysisFailure failure;

  String get message => failure.message;

  @override
  String toString() => 'ChartAnalysisException(${failure.name})';
}
