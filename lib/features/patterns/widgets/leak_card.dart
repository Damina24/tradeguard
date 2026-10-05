import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/trading_leak.dart';

/// One recurring weakness, with its evidence and a cautious next step.
///
/// Pure presentation over a [TradingLeak]. The card's job is to make the finding
/// *checkable*: the title names the slice, the evidence lists the numbers behind
/// it, the sample size is always visible, and the recommendation is hedged in the
/// domain rather than invented here.
///
/// Every element is text. Colour is applied to the result line and the border as a
/// reinforcement only, so the card survives greyscale and colour-blindness.
class LeakCard extends StatelessWidget {
  const LeakCard({required this.leak, super.key});

  final TradingLeak leak;

  @override
  Widget build(BuildContext context) {
    final Color color = AppColors.forPnl(leak.pnl);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.report_problem_outlined, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  leak.title,
                  style: AppTextStyles.title,
                  // Longest realistic titles wrap to two lines; the cap stops a
                  // pathological one from pushing the evidence off the card.
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Evidence bullets: each is a complete sentence built in the domain, so
          // the widget only has to lay them out.
          for (final String line in leak.evidence) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 6, right: 6),
                  child: Icon(
                    Icons.circle,
                    size: 4,
                    color: AppColors.textMuted,
                  ),
                ),
                Expanded(
                  child: Text(line, style: AppTextStyles.muted),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 8),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 10),
          _SampleRow(leak: leak, color: color),
          const SizedBox(height: 8),
          Text(leak.recommendation, style: AppTextStyles.body),
          const SizedBox(height: 8),
          Text(
            leak.confidence.caveat,
            style: AppTextStyles.disclaimer,
          ),
        ],
      ),
    );
  }
}

/// The sample size, stated in words.
///
/// This row is why a leak card can never be mistaken for a fact: the reader sees
/// "based on 24 trades" before they see any interpretation.
class _SampleRow extends StatelessWidget {
  const _SampleRow({required this.leak, required this.color});

  final TradingLeak leak;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          'BASED ON ${leak.trades} '
          'TRADE${leak.trades == 1 ? '' : 'S'}',
          style: AppTextStyles.label,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color),
          ),
          child: Text(
            leak.confidence.label,
            style: AppTextStyles.label.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}