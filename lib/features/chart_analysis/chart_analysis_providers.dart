import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chart_analysis.dart';
import '../../core/services/services.dart';
import 'data/chart_analysis_repository.dart';

enum ChartAnalysisStateStatus { loading, empty, error, ready }

class ChartAnalysisState {
  const ChartAnalysisState({
    this.status = ChartAnalysisStateStatus.empty,
    this.analysis,
    this.isStaleFailure = false,
    this.isStubbed = false,
  });

  factory ChartAnalysisState.error({required bool isStubbed}) {
    return ChartAnalysisState(
      status: ChartAnalysisStateStatus.error,
      isStubbed: isStubbed,
    );
  }

  final ChartAnalysisStateStatus status;
  final ChartAnalysis? analysis;
  final bool isStaleFailure;
  final bool isStubbed;

  bool get isReady => status == ChartAnalysisStateStatus.ready;
}

class ChartAnalysisNotifier
    extends StateNotifier<ChartAnalysisState> {
  ChartAnalysisNotifier(this._repo, this._imageUrl)
      : super(ChartAnalysisState(isStubbed: _repo.isStubbed)) {
    unawaited(refresh());
  }

  final ChartAnalysisRepository _repo;
  final String _imageUrl;

  Future<void> refresh() async {
    try {
      if (!mounted) return;
      state = ChartAnalysisState(
        status: ChartAnalysisStateStatus.loading,
        analysis: state.analysis,
        isStubbed: _repo.isStubbed,
      );
      await _repo.fetchAnalysis();
      if (!mounted) return;
      final ChartAnalysis fresh =
          await _repo.requestAnalysis(_imageUrl);
      if (!mounted) return;
      state = ChartAnalysisState(
        status: ChartAnalysisStateStatus.ready,
        analysis: fresh,
        isStubbed: _repo.isStubbed,
      );
    } catch (_) {
      if (!mounted) return;
      if (state.status == ChartAnalysisStateStatus.ready) {
        state = ChartAnalysisState(
          status: ChartAnalysisStateStatus.ready,
          analysis: state.analysis,
          isStubbed: state.isStubbed,
          isStaleFailure: true,
        );
        return;
      }
      state = ChartAnalysisState.error(isStubbed: _repo.isStubbed);
    }
  }
}

final StateNotifierProviderFamily<ChartAnalysisNotifier,
        ChartAnalysisState, String> chartAnalysisProvider =
    StateNotifierProvider.family<ChartAnalysisNotifier,
        ChartAnalysisState, String>(
      (Ref ref, String imageUrl) => ChartAnalysisNotifier(
        Services.instance.chartAnalysis,
        imageUrl,
      ),
    );
