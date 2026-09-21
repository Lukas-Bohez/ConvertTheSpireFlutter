import 'dart:math';

import 'package:flutter/material.dart';

enum SnackLevel { info, success, warning, error }

class Snack {
  static final Random _random = Random();

  /// Light-hearted headlines shown above every error so failures are easy to
  /// spot at a glance. The real message always follows underneath.
  static const List<String> funnyErrorTitles = [
    'Well, that did not go to plan.',
    'Oops! The hamsters powering this app tripped.',
    'Houston, we have a tiny problem.',
    'That button was not supposed to do that.',
    'Error! But hey, at least the app is honest.',
    'Something exploded (gently).',
    'The bits got tangled. Sorry!',
    'Nope. Not today.',
    'Plot twist: that failed.',
    'Even the best apps have bad days.',
    'Beep boop... error detected.',
    'We poked it and it poked back.',
  ];

  static String _funnyTitle() =>
      funnyErrorTitles[_random.nextInt(funnyErrorTitles.length)];

  static void show(
    BuildContext context,
    String message, {
    SnackLevel level = SnackLevel.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;
    final isError = level == SnackLevel.error;
    if (isError && duration < const Duration(seconds: 5)) {
      duration = const Duration(seconds: 5);
    }
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
            Icon(isError ? Icons.bug_report_rounded : icon,
                color: fgColor, size: isError ? 24 : 18),
            const SizedBox(width: 10),
            Expanded(
              child: isError
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _funnyTitle(),
                          style: TextStyle(
                              color: fgColor, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(message, style: TextStyle(color: fgColor)),
                      ],
                    )
                  : Text(
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
          side: isError
              ? BorderSide(color: cs.error, width: 2)
              : BorderSide.none,
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
