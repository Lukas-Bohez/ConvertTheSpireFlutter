import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Adds consistent Android TV remote/D-pad navigation across the app.
class TvDpadScope extends StatelessWidget {
  final Widget child;
  final bool directionalModeEnabled;
  final VoidCallback? onDirectionalInputDetected;
  final VoidCallback? onPointerInputDetected;

  const TvDpadScope({
    super.key,
    required this.child,
    required this.directionalModeEnabled,
    this.onDirectionalInputDetected,
    this.onPointerInputDetected,
  });

  bool _isDirectionalKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack;
  }

  Widget _buildDirectionalLayer(BuildContext context) {
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
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allowDirectionalScope = !kIsWeb && directionalModeEnabled;
    final wrappedChild = allowDirectionalScope
        ? _buildDirectionalLayer(context)
        : child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onPointerInputDetected?.call(),
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent && _isDirectionalKey(event.logicalKey)) {
            onDirectionalInputDetected?.call();
          }
          return KeyEventResult.ignored;
        },
        child: wrappedChild,
      ),
    );
  }
}