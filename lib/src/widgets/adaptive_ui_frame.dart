import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AdaptiveUiFrame extends StatelessWidget {
  final Widget child;

  const AdaptiveUiFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    final wide = width >= 840;
    // Keep overscan-style framing only for Android TV-style directional UIs.
    final tvLike = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        width > 1200 &&
        mq.navigationMode == NavigationMode.directional;

    final targetSize = wide ? const Size(56, 56) : const Size(48, 48);
    final scale = width > 1200
        ? math.max(1.15, mq.textScaler.scale(1.0))
        : mq.textScaler.scale(1.0);

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final themed = theme.copyWith(
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: targetSize,
          tapTargetSize: MaterialTapTargetSize.padded,
          focusColor: cs.primary.withValues(alpha: 0.16),
          hoverColor: cs.primary.withValues(alpha: 0.08),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: targetSize,
          tapTargetSize: MaterialTapTargetSize.padded,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return cs.primary.withValues(alpha: 0.20);
            }
            if (states.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.12);
            }
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: targetSize,
          tapTargetSize: MaterialTapTargetSize.padded,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return cs.primary.withValues(alpha: 0.20);
            }
            if (states.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.12);
            }
            return null;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: targetSize,
          tapTargetSize: MaterialTapTargetSize.padded,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return cs.primary.withValues(alpha: 0.20);
            }
            if (states.contains(WidgetState.hovered)) {
              return cs.primary.withValues(alpha: 0.12);
            }
            return null;
          }),
        ),
      ),
    );

    final content = Theme(
      data: themed,
      child: MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    );

    if (!tvLike) return content;

    return Padding(
      // TODO(next): add per-screen overscan opt-outs for full-bleed video pages.
      padding: const EdgeInsets.all(24),
      child: content,
    );
  }
}
