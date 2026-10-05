import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/trade.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/price_bar.dart';
import '../domain/price_series_request.dart';
import '../domain/replay_setup.dart';
import '../replay_providers.dart';

/// The setup controls: symbol, timeframe, direction, stop distance, lots.
///
/// Design intent: **the trader sets a stop DISTANCE and a target R, not three prices.** Deriving
/// entry/stop/target from the bar the cursor is on is what makes this usable — asking someone to type
/// 2345.50 / 2338.00 / 2360.00 before they can see anything is a wall, and a wall is why backtest
/// screens go unused. The derived levels are still shown, so nothing is hidden behind an abstraction.
///
/// The controls validate through [ReplaySetup.validationError] rather than through local checks, so
/// the form and the engine can never disagree about what is scorable.
class ReplaySetupForm extends ConsumerWidget {
  const ReplaySetupForm({required this.cursorBar, super.key});

  /// The bar the replay is currently on, or null before any bar has been revealed.
  final PriceBar? cursorBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PriceSeriesRequest request = ref.watch(selectedSeriesProvider);
    final ReplaySetup? setup = ref.watch(replaySetupProvider);
    final List<PriceSeriesRequest> series =
        ref.watch(priceCatalogueProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('SYMBOL', style: AppTextStyles.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final PriceSeriesRequest s in series)
              ChoiceChip(
                label: Text(s.symbol),
                selected: s.symbol == request.symbol,
                // Switching symbol resets the cursor, because bar 200 of XAUUSD means nothing on
                // EURUSD. Leaving the cursor alone would show a chart with no data at that index.
                onSelected: (_) {
                  ref.read(selectedSeriesProvider.notifier).state = s;
                  ref.read(replayCursorProvider.notifier).state = 0;
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('DIRECTION', style: AppTextStyles.label),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _DirectionButton(
                label: 'LONG',
                icon: Icons.trending_up,
                color: AppColors.primary,
                selected: setup?.direction == TradeDirection.long,
                onTap: () => _apply(
                  ref,
                  direction: TradeDirection.long,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DirectionButton(
                label: 'SHORT',
                icon: Icons.trending_down,
                color: AppColors.danger,
                selected: setup?.direction == TradeDirection.short,
                onTap: () => _apply(
                  ref,
                  direction: TradeDirection.short,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _StopDistanceSlider(
          setup: setup,
          onChanged: (double multiple) => _apply(ref, rangeMultiple: multiple),
        ),
        const SizedBox(height: 8),
        _TargetRSelector(
          setup: setup,
          onChanged: (double r) => _apply(ref, targetR: r),
        ),
        if (setup != null) ...<Widget>[
          const SizedBox(height: 16),
          _DerivedLevels(setup: setup),
        ],
      ],
    );
  }

  /// Builds a setup from the cursor bar, preserving whatever the trader had already chosen.
  ///
  /// Falls back to the first visible bar when the cursor is at zero, so the form is usable before the
  /// trader has pressed step. A form that cannot be filled until the transport has been used is a
  /// form most people never fill.
  void _apply(
    WidgetRef ref, {
    TradeDirection? direction,
    double? rangeMultiple,
    double? targetR,
  }) {
    final ReplaySetup? current = ref.read(replaySetupProvider);
    final PriceSeriesRequest request = ref.read(selectedSeriesProvider);
    final PriceBar? bar = cursorBar ?? _firstVisibleBar(ref);

    if (bar == null) return;

    final TradeDirection dir = direction ??
        current?.direction ??
        TradeDirection.long;
    final double multiple = rangeMultiple ??
        current?.rangeMultiple ??
        ReplaySetupForm.defaultRangeMultiple;
    final double? chosenR = targetR ?? current?.targetR;
    // Zero is the "no target" sentinel from `_TargetRSelector`, so it must CLEAR the target rather
    // than place one on top of the entry. Without this the chip would show "No target" selected while
    // the setup still carried a target at 0R.
    final bool clearTarget = chosenR != null && chosenR <= 0;
    final double r =
        clearTarget ? ReplaySetupForm.defaultTargetR : (chosenR ?? ReplaySetupForm.defaultTargetR);

    ReplaySetup next = ReplaySetup.around(
      symbol: request.symbol,
      direction: dir,
      referencePrice: bar.close,
      range: bar.range * multiple,
      targetR: r,
      lots: current?.lots ?? ReplaySetupForm.defaultLots,
    ).copyWith(rangeMultiple: multiple, targetR: r);

    if (clearTarget) next = next.copyWith(clearTarget: true);

    ref.read(replaySetupProvider.notifier).state = next;
  }

  PriceBar? _firstVisibleBar(WidgetRef ref) {
    final List<PriceBar> bars = ref.read(visibleBarsProvider);
    return bars.isEmpty ? null : bars.last;
  }

  /// One bar's range as the stop distance. Tight enough to be a real gold/FX stop.
  static const double defaultRangeMultiple = 1.0;

  /// A 1:2 default, because it is the ratio the setup card teaches and the one a trader is most
  /// likely to be testing.
  static const double defaultTargetR = 2.0;

  static const double defaultLots = 1.0;
}

/// Long/short. Two big targets, because this is the most consequential choice on the screen and it
/// must not be a small control.
class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 18, color: selected ? color : AppColors.textMuted),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.title.copyWith(
                color: selected ? color : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stop width, in bar-ranges. Continuous rather than discrete because the trader is choosing a
/// distance, and snapping it to presets would make the exact width they want unreachable.
class _StopDistanceSlider extends StatelessWidget {
  const _StopDistanceSlider({required this.setup, required this.onChanged});

  final ReplaySetup? setup;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final double current =
        setup?.rangeMultiple ?? ReplaySetupForm.defaultRangeMultiple;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            // BOTH sides are flexible, and that is the whole point of this row.
            //
            // `Row` lays out non-flex children with an UNBOUNDED main-axis constraint, so the two
            // `Text`s here take their full intrinsic widths and `Spacer` is then left with nothing —
            // it cannot rescue an overflow it only gets to see after the damage is done. With the
            // pip note appended ("1.0 bar range · 30 pips") the pair exceeded a 390px screen and threw
            // a RenderFlex overflow. Flexible on both sides lets them share the width and ellipsize
            // instead, which is what a label/value row should do on a narrow phone anyway.
            const Expanded(
              child: Text(
                'STOP WIDTH',
                style: AppTextStyles.label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _widthNote(setup, current),
                style: AppTextStyles.muted,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Slider(
          value: current.clamp(0.25, 4.0),
          min: 0.25,
          max: 4.0,
          divisions: 15,
          label: '${current.toStringAsFixed(2)}×',
          activeColor: AppColors.accent,
          onChanged: onChanged,
        ),
      ],
    );
  }

  static String _widthNote(ReplaySetup? setup, double current) {
    final double? pips = setup?.riskPips;
    final String width = '${current.toStringAsFixed(1)} bar range';
    return pips == null ? width : '$width · ${pips.toStringAsFixed(0)} pips';
  }
}

/// Target R. Includes "no target", because letting a trade run is a real thing traders want to test —
/// and the engine reports that outcome as unresolved rather than inventing an exit.
class _TargetRSelector extends StatelessWidget {
  const _TargetRSelector({required this.setup, required this.onChanged});

  final ReplaySetup? setup;

  /// Receives the chosen R. **Zero means "remove the target"**, which is how [ReplaySetupForm._apply]
  /// expresses `copyWith(clearTarget: true)` — a `double` can carry that, a nullable `double` cannot.
  final void Function(double) onChanged;

  static const List<double> options = <double>[1, 1.5, 2, 3];

  @override
  Widget build(BuildContext context) {
    final double? current = setup?.rewardRisk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('TARGET', style: AppTextStyles.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final double option in options)
              ChoiceChip(
                label: Text('${_fmt(option)}R'),
                selected: current != null && (current - option).abs() < 0.01,
                onSelected: (_) => onChanged(option),
              ),
            ChoiceChip(
              label: const Text('No target'),
              selected: setup != null && setup!.target == null,
              onSelected: (_) => onChanged(0),
            ),
          ],
        ),
      ],
    );
  }

  /// Plain decimals rather than fractions: in a trading context "1.5" and "1:5" get confused in copy,
  /// and an ambiguous ratio is worse than a plainer one.
  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// The levels the controls produced, spelled out.
///
/// Never hidden behind the sliders: a trader has to be able to check the actual prices, because those
/// are what a real order would use.
class _DerivedLevels extends StatelessWidget {
  const _DerivedLevels({required this.setup});

  final ReplaySetup setup;

  @override
  Widget build(BuildContext context) {
    final String? error = setup.validationError;
    if (error != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 14, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              error,
              style: AppTextStyles.disclaimer.copyWith(color: AppColors.warning),
            ),
          ),
        ],
      );
    }

    final double? riskPct = setup.accountRiskPct;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // One level per line rather than three prices packed into a single string. A run-on line
          // has to fit `ENTRY 1.08720   STOP 1.08520   TARGET 1.09120` on a 320px screen, and at
          // five-decimal precision it does not — which is a real overflow, not a test artefact, and
          // the stacked form also reads better as a block of prices.
          _level('Entry', _p(setup.entry)),
          _level('Stop', _p(setup.stop)),
          _level(
            'Target',
            setup.target == null ? 'No target' : _p(setup.target!),
          ),
          const SizedBox(height: 8),
          Text(
            '${setup.lots.toStringAsFixed(2)} lots · risks '
            '${riskPct == null ? '—' : '${riskPct.toStringAsFixed(2)}%'} of the account',
            style: AppTextStyles.disclaimer,
          ),
        ],
      ),
    );
  }

  /// One level: the name left-aligned, the price right-aligned.
  ///
  /// [Expanded] on the label rather than on the value, so the number keeps its full width and the
  /// word is what gets truncated on a very narrow screen — a clipped price is worse than a clipped
  /// label.
  Widget _level(String name, String price) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(name, style: AppTextStyles.muted)),
            Text(price, style: AppTextStyles.body),
          ],
        ),
      );

  static String _p(double v) => v.toStringAsFixed(v.abs() < 10 ? 5 : 2);
}