import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../domain/replay_result.dart';
import '../domain/replay_setup.dart';

/// What one replayed setup did.
///
/// Presentation only. Every number is read off [ReplayResult] / [ReplaySetup]; this file contains no
/// arithmetic and, in particular, does not decide whether an outcome was GOOD.
///
/// Five states, each with its own words, because they are five different facts:
///
///   * **no setup yet** — nothing to replay. Not an error.
///   * **invalid** — the levels cannot be scored, so [ReplaySetup.validationError] is shown verbatim
///     rather than a generic "bad input".
///   * **never filled** — price never reached the entry. Explicitly NOT a loss: nothing traded, and a
///     card showing this as a red "-1R" would be inventing a trade.
///   * **unresolved** — filled and still open when the visible data ran out. Marked to market and
///     labelled "still open", never presented as a result.
///   * **resolved** — target or stop, with the bar it happened on.
class ReplayVerdictCard extends StatelessWidget {
  const ReplayVerdictCard({
    required this.setup,
    required this.result,
    this.visibleBars = 0,
    super.key,
  });

  /// Null until the trader has chosen levels.
  final ReplaySetup? setup;

  /// Null when there is no valid setup to run, or no bars yet.
  final ReplayResult? result;

  /// How many bars the replay was allowed to see. Stated so the trader can tell what they are judging.
  final int visibleBars;

  @override
  Widget build(BuildContext context) {
    final ReplaySetup? s = setup;
    if (s == null) return const _NoSetup();

    final ReplayResult? r = result;
    if (r == null) {
      return const _CardShell(
        child: _StateNote(
          icon: Icons.hourglass_empty,
          title: 'No result yet',
          message:
              'Step forward through the bars to see what this setup would have done.',
        ),
      );
    }

    switch (r.status) {
      case ReplayStatus.invalid:
        return _CardShell(
          child: _StateNote(
            icon: Icons.error_outline,
            title: 'This setup cannot be replayed',
            message: s.validationError ?? 'Check the entry, stop and target.',
            color: AppColors.warning,
          ),
        );
      case ReplayStatus.notFilled:
        return _CardShell(
          child: _StateNote(
            icon: Icons.trending_flat,
            title: 'Price never reached the entry',
            message: 'Nothing would have traded over these $visibleBars bars. That '
                'is not a loss — the setup simply never triggered.',
          ),
        );
      case ReplayStatus.unresolved:
        return _Open(setup: s, result: r, visibleBars: visibleBars);
      case ReplayStatus.targetHit:
      case ReplayStatus.stopHit:
        return _Resolved(setup: s, result: r, visibleBars: visibleBars);
    }
  }
}

/// A resolved outcome: the target or the stop was reached.
class _Resolved extends StatelessWidget {
  const _Resolved({
    required this.setup,
    required this.result,
    required this.visibleBars,
  });

  final ReplaySetup setup;
  final ReplayResult result;
  final int visibleBars;

  @override
  Widget build(BuildContext context) {
    final bool won = result.isWin;
    final Color color = won ? AppColors.primary : AppColors.danger;

    return _CardShell(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Heading(
            icon: won ? Icons.trending_up : Icons.trending_down,
            color: color,
            label: won ? 'TARGET REACHED' : 'STOP HIT',
          ),
          const SizedBox(height: 12),
          _Headline(
            rMultiple: result.rMultiple,
            money: result.pnl,
            lots: setup.lots,
            color: color,
          ),
          const SizedBox(height: 12),
          _Evidence(result: result, setup: setup),
          const SizedBox(height: 12),
          Text(
            'Resolved on bar ${result.exitIndex} of $visibleBars. The fill rules are '
            'pessimistic: a bar spanning both the stop and the target is always counted as '
            'the stop, because OHLC cannot show which came first.',
            style: AppTextStyles.disclaimer,
          ),
        ],
      ),
    );
  }
}

/// Filled, and still open when the bars on screen ran out.
class _Open extends StatelessWidget {
  const _Open({
    required this.setup,
    required this.result,
    required this.visibleBars,
  });

  final ReplaySetup setup;
  final ReplayResult result;
  final int visibleBars;

  @override
  Widget build(BuildContext context) {
    final double? r = result.rMultiple;
    return _CardShell(
      accent: AppColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Heading(
            icon: Icons.timelapse,
            color: AppColors.warning,
            label: 'STILL OPEN',
          ),
          const SizedBox(height: 8),
          const Text(
            'Neither the stop nor the target was reached in the bars shown. The figure below '
            'is the mark at the last close, not a closed result.',
            style: AppTextStyles.muted,
          ),
          const SizedBox(height: 12),
          _Headline(
            rMultiple: r,
            money: result.pnl,
            lots: setup.lots,
            color: (r ?? 0) >= 0 ? AppColors.primary : AppColors.danger,
            suffix: 'marked over $visibleBars bars',
          ),
          const SizedBox(height: 12),
          _Evidence(result: result, setup: setup),
        ],
      ),
    );
  }
}

/// The R headline plus its money equivalent. Money is secondary, never the lead figure.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.rMultiple,
    required this.money,
    required this.lots,
    required this.color,
    this.suffix,
  });

  final double? rMultiple;
  final double? money;
  final double lots;
  final Color color;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    // An unscorable result shows a dash, not a zero — a zero would read as a verdict about a trade
    // nobody assessed.
    final double? value = rMultiple;
    final String headline = value == null
        ? '—'
        : '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}R';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(headline, style: AppTextStyles.metric.copyWith(color: color)),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              suffix ??
                  '${_signedMoney(money ?? 0)} on ${lots.toStringAsFixed(2)} lots',
              style: AppTextStyles.muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// The evidence: what the replay actually did, bar by bar.
///
/// This is the part that makes the card auditable rather than a score. Every null renders as a dash,
/// never a zero — a zero would be a claim that the trade moved exactly nothing.
class _Evidence extends StatelessWidget {
  const _Evidence({required this.result, required this.setup});

  final ReplayResult result;
  final ReplaySetup setup;

  @override
  Widget build(BuildContext context) {
    final bool gapped =
        result.fillPrice != null && result.fillPrice != setup.entry;
    return Column(
      children: <Widget>[
        _row('Filled at', _price(result.fillPrice), gapped ? 'gapped' : ''),
        _row('Exited at', _price(result.exitPrice), 'bar ${result.exitIndex ?? 0}'),
        _row(
          'Held for',
          result.barsHeld == null ? '—' : '${result.barsHeld} bars',
          '',
        ),
        _row('Best it reached', _r(result.mfeR), 'MFE'),
        _row('Worst it reached', _r(result.maeR), 'MAE'),
        _row(
          'Stop distance',
          setup.riskPips == null
              ? '—'
              : '${setup.riskPips!.toStringAsFixed(1)} pips',
          '',
        ),
      ],
    );
  }

  Widget _row(String label, String value, String note) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: Text(label, style: AppTextStyles.muted)),
            Text(value, style: AppTextStyles.body),
            if (note.isNotEmpty) ...<Widget>[
              const SizedBox(width: 6),
              Text(note, style: AppTextStyles.disclaimer),
            ],
          ],
        ),
      );

  static String _r(double? value) =>
      value == null ? '—' : '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}R';

  static String _price(double? value) =>
      value == null ? '—' : value.toStringAsFixed(value.abs() < 10 ? 5 : 2);
}

/// Icon + word. Every verdict in this file names itself, so nothing depends on colour alone.
class _Heading extends StatelessWidget {
  const _Heading({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label, style: AppTextStyles.label.copyWith(color: color)),
      ],
    );
  }
}

/// The card container. One border treatment, so every state reads as the same object.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final Color? a = accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: a == null
              ? AppColors.divider
              : Color.alphaBlend(a.withValues(alpha: 0.35), AppColors.divider),
        ),
      ),
      child: child,
    );
  }
}

String _signedMoney(double v) =>
    '${v >= 0 ? '+' : '-'}${Formatters.money(v.abs())}';

class _NoSetup extends StatelessWidget {
  const _NoSetup();

  @override
  Widget build(BuildContext context) {
    return const _CardShell(
      child: _StateNote(
        icon: Icons.tune,
        title: 'Set up a trade to replay',
        message: 'Pick a direction and a stop above. The replay fills at the first bar that '
            'trades through your entry, then follows it bar by bar until the stop or the target.',
      ),
    );
  }
}

/// A state with no numbers in it: nothing chosen, nothing triggered, nothing scorable.
class _StateNote extends StatelessWidget {
  const _StateNote({
    required this.icon,
    required this.title,
    required this.message,
    this.color = AppColors.textMuted,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Heading(icon: icon, color: color, label: title.toUpperCase()),
        const SizedBox(height: 8),
        Text(message, style: AppTextStyles.muted),
      ],
    );
  }
}