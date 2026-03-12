import 'package:flutter/material.dart';

/// Small centralized color helpers to ease theming and dark-mode fixes.
extension AppColors on BuildContext {
  /// Primary success color used for positive states.
  Color get success => Theme.of(this).colorScheme.primary;

  /// A container variant for success (lighter/darker depending on theme).
  Color get successContainer => Theme.of(this).colorScheme.primaryContainer;

  /// Warning/attention color.
  Color get warning => Colors.orange;

  /// Text color that works on warning backgrounds.
  Color get onWarning => Colors.white;

  /// Danger color for errors.
  Color get danger => Theme.of(this).colorScheme.error;

  /// Muted text color.
  Color get muted => Theme.of(this).colorScheme.onSurfaceVariant;
}
