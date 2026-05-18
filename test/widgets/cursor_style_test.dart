import 'package:convert_the_spire_reborn/src/widgets/cursor_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns a dark-friendly palette in light mode', () {
    final style = cursorStyleFor(Brightness.light);

    expect(style.fillColor, equals(Colors.black.withValues(alpha: 0.86)));
    expect(style.borderColor, equals(Colors.white.withValues(alpha: 0.9)));
    expect(style.accentColor, equals(Colors.white));
  });

  test('returns a light-friendly palette in dark mode', () {
    final style = cursorStyleFor(Brightness.dark);

    expect(style.fillColor, equals(Colors.white.withValues(alpha: 0.92)));
    expect(style.borderColor, equals(Colors.black.withValues(alpha: 0.9)));
    expect(style.accentColor, equals(Colors.black));
  });
}