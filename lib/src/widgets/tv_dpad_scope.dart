import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Adds consistent Android TV remote/D-pad navigation across the app.
class TvDpadScope extends StatelessWidget {
  final Widget child;

  const TvDpadScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDirectionalTv = !kIsWeb &&
        Platform.isAndroid &&
        MediaQuery.of(context).navigationMode == NavigationMode.directional;

    if (!isDirectionalTv) {
      return child;
    }

    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowUp):
              DirectionalFocusIntent(TraversalDirection.up),
          SingleActivator(LogicalKeyboardKey.arrowDown):
              DirectionalFocusIntent(TraversalDirection.down),
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              DirectionalFocusIntent(TraversalDirection.left),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              DirectionalFocusIntent(TraversalDirection.right),
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DirectionalFocusIntent: DirectionalFocusAction(),
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (intent) {
                final nav = Navigator.maybeOf(context);
                if (nav?.canPop() ?? false) {
                  nav!.maybePop();
                }
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: child,
          ),
        ),
      ),
    );
  }
}