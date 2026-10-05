import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../domain/price_bar.dart';
import '../domain/replay_result.dart';
import '../domain/replay_setup.dart';

/// The price line, with the setup's levels drawn on it.
///
/// ## Why this chart is drawn by hand rather than reusing a chart component
///
/// The entry, stop and target lines ARE the analysis: a trader reading a backtest is asking "did price
/// reach my level before it hit my stop", and that question cannot be answered from a chart showing
/// only a line. So the levels are drawn here, and [ReplaySetup] / [ReplayResult] supply them — this
/// file contains no arithmetic and no thresholds of its own.
///
/// Three things it is careful about:
///
///   * **The window always includes the levels.** A long's stop can sit below every bar in view, and a
///     chart that clipped it would silently hide the very risk the trader is measuring.
///   * **Meaning never rests on colour.** Each line is named in the legend beneath, so the chart
///     survives greyscale and colour-blindness.
///   * **It draws nothing it cannot label.** No bars → an explicit empty state, not an empty axis.
class ReplayChart extends StatelessWidget {
  const ReplayChart({
    required this.bars,
    this.setup,
    this.result,
    super.key,
  });

  final List<PriceBar> bars;
  final ReplaySetup? setup;

  /// Accepted so a caller can pass the verdict straight through, and so the chart's contract matches
  /// the screen's. Unused for drawing today: the exit marker is read off the RESULT card below, which
  /// states it in words. Kept rather than omitted so adding a marker later does not change this
  /// widget's signature.
  final ReplayResult? result;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text('No bars to draw', style: AppTextStyles.muted),
        ),
      );
    }

    final ReplaySetup? s = setup;
    final ({double low, double high}) window = _window(bars, s);

    // A flat range would make the chart divide by zero. A synthetic band avoids that, and only arises
    // when every visible bar closed at the same price.
    final double span = window.high - window.low;
    final double pad = span > 0 ? span * 0.06 : (window.high.abs() * 0.001 + 0.0001);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (bars.length - 1).toDouble(),
              minY: window.low - pad,
              maxY: window.high + pad,
              clipData: const FlClipData.all(),
              gridData: const FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: _gridLine,
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    interval: span / 3,
                    getTitlesWidget: (double value, TitleMeta meta) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        value.toStringAsFixed(_decimals(bars)),
                        style: AppTextStyles.disclaimer,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                ),
                bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              extraLinesData: _levels(s),
              lineBarsData: <LineChartBarData>[_priceLine(bars)],
            ),
          ),
        ),
        if (s != null) _LevelLegend(setup: s),
      ],
    );
  }

  static LineChartBarData _priceLine(List<PriceBar> bars) => LineChartBarData(
        spots: <FlSpot>[
          for (int i = 0; i < bars.length; i++)
            FlSpot(i.toDouble(), bars[i].close),
        ],
        isCurved: false,
        barWidth: 1.6,
        color: AppColors.accent,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: AppColors.accent.withValues(alpha: 0.10),
        ),
      );

  /// The vertical window: the bars' own extremes, widened to cover the setup's levels.
  ///
  /// This is the one place that reconciles "where did price go" with "where are the levels", and
  /// keeping it here means the model never needs to know it is about to be drawn.
  static ({double low, double high}) _window(
    List<PriceBar> bars,
    ReplaySetup? setup,
  ) {
    final ({double low, double high})? seen = _extremes(bars);
    double low = seen?.low ?? 0;
    double high = seen?.high ?? 1;
    if (setup != null) {
      for (final double level in <double>[
        setup.entry,
        setup.stop,
        if (setup.target != null) setup.target!,
      ]) {
        if (level < low) low = level;
        if (level > high) high = level;
      }
    }
    return (low: low, high: high);
  }

  static ({double low, double high})? _extremes(List<PriceBar> bars) {
    if (bars.isEmpty) return null;
    double low = bars.first.low;
    double high = bars.first.high;
    for (final PriceBar b in bars) {
      if (b.low < low) low = b.low;
      if (b.high > high) high = b.high;
    }
    return (low: low, high: high);
  }

  /// Entry, stop and target as horizontal lines. Dashed for the stop and target so they are
  /// distinguishable from the price line even in a greyscale printout.
  static ExtraLinesData _levels(ReplaySetup? setup) {
    if (setup == null) return const ExtraLinesData();
    return ExtraLinesData(
      horizontalLines: <HorizontalLine>[
        HorizontalLine(
          y: setup.entry,
          color: AppColors.textMuted,
          strokeWidth: 1,
        ),
        HorizontalLine(
          y: setup.stop,
          color: AppColors.danger,
          strokeWidth: 1.2,
          dashArray: <int>[6, 4],
        ),
        if (setup.target != null)
          HorizontalLine(
            y: setup.target!,
            color: AppColors.primary,
            strokeWidth: 1.2,
            dashArray: <int>[6, 4],
          ),
      ],
    );
  }

  static FlLine _gridLine(double value) => const FlLine(
    color: AppColors.divider,
    strokeWidth: 1,
    dashArray: <int>[4, 4],
  );

  /// Axis precision inferred from the data, so EURUSD reads 1.08720 and XAUUSD reads 2345.50.
  ///
  /// Derived rather than a per-symbol table: `MockPriceBarRepository` already rounds to each symbol's
  /// precision, and duplicating that list here would be a second place to forget a symbol.
  static int _decimals(List<PriceBar> bars) {
    if (bars.isEmpty) return 2;
    final double value = bars.last.close.abs();
    if (value < 10) return 5;
    if (value < 1000) return 3;
    return 2;
  }
}

/// The legend. Every drawn line is named in words, so nothing is conveyed by colour alone.
class _LevelLegend extends StatelessWidget {
  const _LevelLegend({required this.setup});

  final ReplaySetup setup;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: <Widget>[
          _item('Entry', setup.entry, AppColors.textMuted),
          _item('Stop', setup.stop, AppColors.danger),
          if (setup.target != null)
            _item('Target', setup.target!, AppColors.primary),
        ],
      ),
    );
  }

  Widget _item(String label, double price, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(width: 12, height: 2, color: color),
          const SizedBox(width: 6),
          Text(
            '$label ${price.toStringAsFixed(price.abs() < 10 ? 5 : 2)}',
            style: AppTextStyles.disclaimer,
          ),
        ],
      );
}