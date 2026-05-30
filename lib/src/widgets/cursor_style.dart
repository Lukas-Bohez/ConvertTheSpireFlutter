import 'package:flutter/material.dart';

class CursorStyle {
  final Color fillColor;
  final Color borderColor;
  final Color accentColor;

  const CursorStyle({
    required this.fillColor,
    required this.borderColor,
    required this.accentColor,
  });
}

CursorStyle cursorStyleFor(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return CursorStyle(
    fillColor: isDark
        ? Colors.white.withValues(alpha: 0.92)
        : Colors.black.withValues(alpha: 0.86),
    borderColor: isDark
        ? Colors.black.withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: 0.9),
    accentColor: isDark ? Colors.black : Colors.white,
  );
}
