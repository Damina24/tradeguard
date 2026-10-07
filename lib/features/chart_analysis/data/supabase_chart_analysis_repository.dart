import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/chart_analysis.dart';
import '../../../core/services/supabase_service.dart';
import 'chart_analysis_repository.dart';

/// Live analysis via the ai-analyze-chart Edge Function.
class SupabaseChartAnalysisRepository
    implements ChartAnalysisRepository {
  SupabaseChartAnalysisRepository([SupabaseService? s])
      : _service = s ?? SupabaseService.instance;

  final SupabaseService _service;

  SupabaseClient get _client => _service.client;

  @override
  bool get isStubbed => false;

  @override
  Future<ChartAnalysis?> fetchAnalysis() async => null;

  @override
  Future<ChartAnalysis> requestAnalysis(String imageUrl) async {
    final dynamic res;
    try {
      res = await _client.functions.invoke(
        'ai-analyze-chart',
        body: <String, dynamic>{'image_url': imageUrl},
      );
    } on FunctionsHttpException catch (e) {
      throw ChartAnalysisException(_classify(e.status));
    } catch (_) {
      throw const ChartAnalysisException(
        ChartAnalysisFailure.unreachable,
      );
    }
    final Object? data = res.data as Object?;
    if (data is! Map<String, dynamic>) {
      throw const ChartAnalysisException(
        ChartAnalysisFailure.malformed,
      );
    }
    try {
      return ChartAnalysis.fromJson(data);
    } catch (_) {
      throw const ChartAnalysisException(
        ChartAnalysisFailure.malformed,
      );
    }
  }

  static ChartAnalysisFailure _classify(int s) {
    if (s == 401) return ChartAnalysisFailure.unauthorized;
    if (s == 403) return ChartAnalysisFailure.forbidden;
    if (s == 404) return ChartAnalysisFailure.unavailable;
    if (s == 422) return ChartAnalysisFailure.invalidImage;
    if (s == 503) return ChartAnalysisFailure.notConfigured;
    if (s == 502) return ChartAnalysisFailure.malformed;
    return ChartAnalysisFailure.failed;
  }
}
