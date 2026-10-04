import 'package:flutter/material.dart';

/// TradeGuard color tokens. Dark theme is primary.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0A0E17);
  static const Color surface = Color(0xFF121826);
  static const Color surfaceAlt = Color(0xFF1A2233);
  static const Color primary = Color(0xFF00E676); // safe / profit
  static const Color warning = Color(0xFFFFB300);
  static const Color danger = Color(0xFFFF3D5A); // loss
  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textMuted = Color(0xFF8A94A6);
  static const Color accent = Color(0xFF3B82F6);
  static const Color divider = Color(0xFF232C40);

  static Color forPnl(double value) => value >= 0 ? primary : danger;
}
