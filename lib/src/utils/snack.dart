import 'package:flutter/material.dart';

enum SnackLevel { info, success, warning, error }

class Snack {
  static void show(
    BuildContext context,
    String message, {
    SnackLevel level = SnackLevel.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;
    final cs = Theme.of(context).colorScheme;

    final bgColor = switch (level) {
      SnackLevel.success => cs.primaryContainer,
      SnackLevel.warning => cs.tertiaryContainer,
      SnackLevel.error => cs.errorContainer,
      SnackLevel.info => cs.surfaceContainer,
    };

    final fgColor = switch (level) {
      SnackLevel.success => cs.onPrimaryContainer,
      SnackLevel.warning => cs.onTertiaryContainer,
      SnackLevel.error => cs.onErrorContainer,
      SnackLevel.info => cs.onSurface,
    };

    final icon = switch (level) {
      SnackLevel.success => Icons.check_circle_rounded,
      SnackLevel.warning => Icons.warning_amber_rounded,
      SnackLevel.error => Icons.error_rounded,
      SnackLevel.info => Icons.info_rounded,
    };

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: fgColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: fgColor),
              ),
            ),
          ],
        ),
        backgroundColor: bgColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(12),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel, textColor: fgColor, onPressed: onAction)
            : null,
      ),
    );
  }
}
