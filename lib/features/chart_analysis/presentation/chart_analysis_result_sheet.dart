import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/chart_analysis.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Full analysis result sheet with risk disclaimer.
class ChartAnalysisResultSheet extends StatelessWidget {
  const ChartAnalysisResultSheet({
    super.key,
    required this.analysis,
    required this.isStubbed,
  });

  final ChartAnalysis analysis;
  final bool isStubbed;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(isStubbed ? 'OFFLINE DEMO' : 'Analysis'),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
          Text(analysis.bias.label),
          Text(analysis.bias.desc),
          if (analysis.levels.isNotEmpty)
            Text(analysis.levels.join(', ')),
          if (analysis.note.isNotEmpty)
            Text(analysis.note),
          const SizedBox(height: 16),
          const Text(
            AppStrings.riskDisclaimer,
            style: AppTextStyles.disclaimer,
          ),
        ],
      ),
    );
  }
}
