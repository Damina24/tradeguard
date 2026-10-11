import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// A soft, looping highlight that sweeps a placeholder box, used while live
/// account data is in flight.
///
/// Built in-app rather than pulled from a shimmer package: the dependency budget
/// is tight, and a two-stop gradient on a timer is all the loading state needs.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    required this.width,
    required this.height,
    this.radius = 8,
    super.key,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        // A highlight that travels left→right and wraps, so the box reads as
        // "loading" without a hard on/off flash.
        final double t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + t * 2, 0),
              end: Alignment(t * 2, 0),
              colors: const <Color>[
                AppColors.surfaceAlt,
                AppColors.divider,
                AppColors.surfaceAlt,
              ],
              stops: const <double>[0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}
