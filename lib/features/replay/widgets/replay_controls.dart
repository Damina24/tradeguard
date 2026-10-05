import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Bar-by-bar transport for the replay: reset, step back, play/pause, step forward, jump to the end.
///
/// This is what makes the feature a *replay* rather than a report. The cursor only ever exposes a
/// prefix of the series (`visibleBarsProvider` does the slicing), so a bar the trader has not stepped
/// to cannot affect the verdict beside the chart.
///
/// Three rules it keeps:
///
///   * **Controls disable, they never lie.** At bar 0 "step back" is disabled rather than resetting
///     silently; at the last bar "step forward" and "play" are disabled rather than doing nothing.
///   * **Every button carries a tooltip.** The transport is icon-only, so the icons are named for
///     screen readers, and the counter states the position in words as well as digits.
///   * **Play is a timer owned here.** It stops by itself at the end of the series and is cancelled on
///     dispose, so navigating away mid-replay cannot leave a timer running.
class ReplayControls extends StatefulWidget {
  const ReplayControls({
    required this.cursor,
    required this.total,
    required this.enabled,
    required this.onSeek,
    super.key,
  });

  /// Which bar is showing, zero-based.
  final int cursor;

  /// How many bars exist in total.
  final int total;

  /// Whether stepping is possible at all (false while bars are still loading).
  final bool enabled;

  /// Called with the new zero-based cursor.
  final ValueChanged<int> onSeek;

  /// How long each bar is held while playing. Slow enough to actually watch a fill happen.
  static const Duration stepInterval = Duration(milliseconds: 550);

  @override
  State<ReplayControls> createState() => _ReplayControlsState();
}

class _ReplayControlsState extends State<ReplayControls> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _isPlaying => _timer != null;

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _togglePlay() {
    if (_isPlaying) {
      setState(_stop);
      return;
    }
    // Play at the end restarts from the beginning. The alternative is a dead button until the trader
    // manually rewinds, which reads as a bug rather than a boundary.
    if (widget.cursor >= widget.total - 1) widget.onSeek(0);

    _timer = Timer.periodic(ReplayControls.stepInterval, (Timer t) {
      if (!mounted || widget.cursor >= widget.total - 1) {
        t.cancel();
        setState(() => _timer = null);
        return;
      }
      widget.onSeek(widget.cursor + 1);
    });
    setState(() {});
  }

  void _step(int delta) {
    _stop();
    setState(() {});
    final int next = widget.cursor + delta;
    if (next < 0 || next > widget.total - 1) return;
    widget.onSeek(next);
  }

  void _seek(int index) {
    _stop();
    setState(() {});
    widget.onSeek(index);
  }

@override
  Widget build(BuildContext context) {
    final bool on = widget.enabled && widget.total > 0;
    final bool atStart = widget.cursor <= 0;
    final bool atEnd = widget.cursor >= widget.total - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
            'BAR ${on ? widget.cursor + 1 : 0} OF ${widget.total}',
            style: AppTextStyles.label,
          ),
            const Spacer(),
            Text(_percent(on), style: AppTextStyles.muted),
          ],
        ),
        const SizedBox(height: 8),
        // Wrap rather than Row: five 48px buttons exceed a 320px screen once padding is counted, and
        // an overflowing control bar is how the reset button quietly becomes unreachable.
        Wrap(
          spacing: 8,
          children: <Widget>[
            _button(
              icon: Icons.replay,
              tooltip: 'Back to the first bar',
              onPressed: on && !atStart ? () => _seek(0) : null,
            ),
            _button(
              icon: Icons.skip_previous,
              tooltip: 'Step back one bar',
              onPressed: on && !atStart ? () => _step(-1) : null,
            ),
            _button(
              icon: _isPlaying ? Icons.pause : Icons.play_arrow,
              tooltip: _isPlaying ? 'Pause the replay' : 'Play the replay',
              onPressed: on && (!atEnd || _isPlaying) ? _togglePlay : null,
              emphasised: true,
            ),
            _button(
              icon: Icons.skip_next,
              tooltip: 'Step forward one bar',
              onPressed: on && !atEnd ? () => _step(1) : null,
            ),
            _button(
              icon: Icons.fast_forward,
              tooltip: 'Skip to the last bar',
              onPressed: on && !atEnd ? () => _seek(widget.total - 1) : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(_positionNote(), style: AppTextStyles.disclaimer),
      ],
    );
  }

  String _percent(bool on) {
    if (!on || widget.total <= 0) return '—';
    return '${(((widget.cursor + 1) / widget.total) * 100).round()}%';
  }

  Widget _button({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool emphasised = false,
  }) =>
      Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: 22,
          // 48px, above the 44px minimum target in UI_UX_DESIGN §7.
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          style: IconButton.styleFrom(
            backgroundColor:
                emphasised ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceAlt,
            foregroundColor:
                onPressed == null ? AppColors.textMuted : AppColors.textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );

  String _positionNote() {
    final int total = widget.total;
    if (total == 0) return 'Nothing loaded yet.';
    if (total < 5) {
      return 'Only $total bars available. A replay needs a few more before a level can be reached.';
    }
    return 'Step forward to reveal each bar in turn. These are historical bars, not a live feed.';
  }
}