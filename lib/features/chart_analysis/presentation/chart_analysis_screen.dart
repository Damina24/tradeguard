import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/chart_analysis.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../chart_analysis_providers.dart';
import 'chart_analysis_result_sheet.dart';

/// AI Chart Analysis screen.
class ChartAnalysisScreen extends ConsumerWidget {
  const ChartAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ChartAnalysisState st =
        ref.watch(chartAnalysisProvider(''));

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chart Analysis'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Card(
            child: InkWell(
              onTap: () => _pick(context, ref),
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.auto_awesome, size: 32),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Upload a chart screenshot.',
                        style: AppTextStyles.body,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (st.status == ChartAnalysisStateStatus.loading)
            const Center(
              child: Text(
                'Analysing chart...',
                style: AppTextStyles.muted,
              ),
            ),
          if (st.status == ChartAnalysisStateStatus.error)
            _ErrorCard(
              isStubbed: st.isStubbed,
              onRetry: () {
                ref
                    .read(chartAnalysisProvider('').notifier)
                    .refresh();
              },
            ),
          if (st.status == ChartAnalysisStateStatus.ready &&
              st.analysis != null)
            _Preview(
              analysis: st.analysis!,
              isStubbed: st.isStubbed,
            ),
          const SizedBox(height: 24),
          const Text(
            AppStrings.riskDisclaimer,
            style: AppTextStyles.disclaimer,
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.isStubbed, required this.onRetry});

  final bool isStubbed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Analysis failed'),
            const SizedBox(height: 8),
            Text(isStubbed ? 'Offline demo failed.' : 'Try again.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.analysis, required this.isStubbed});

  final ChartAnalysis analysis;
  final bool isStubbed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(isStubbed ? 'OFFLINE DEMO' : 'Ready'),
            Text(analysis.bias.label),
            Text(analysis.note),
            OutlinedButton.icon(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: AppColors.surface,
                  builder: (_) => ChartAnalysisResultSheet(
                    analysis: analysis,
                    isStubbed: isStubbed,
                  ),
                );
              },
              icon: const Icon(Icons.visibility),
              label: const Text('View full analysis'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _pick(BuildContext context, WidgetRef ref) async {
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (_) => CupertinoActionSheet(
      actions: <Widget>[
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.of(context).pop();
            ref
                .read(chartAnalysisProvider('').notifier)
                .refresh();
          },
          child: const Text('Upload chart'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    ),
  );
}
