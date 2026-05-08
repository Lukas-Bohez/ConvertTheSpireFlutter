import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

class DpadFocusableSurface extends StatelessWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final bool autofocus;
  final bool enabled;
  final bool autoScroll;
  final String? region;
  final String? debugLabel;
  final bool selected;

  const DpadFocusableSurface({
    super.key,
    required this.child,
    this.onSelect,
    this.autofocus = false,
    this.enabled = true,
    this.autoScroll = false,
    this.region,
    this.debugLabel,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      autofocus: autofocus,
      enabled: enabled,
      autoScroll: autoScroll,
      region: region,
      debugLabel: debugLabel,
      onSelect: onSelect,
      builder: (context, isFocused, child) {
        final cs = Theme.of(context).colorScheme;
        final highlight = isFocused || selected;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight ? cs.primary : Colors.transparent,
              width: 2,
            ),
            boxShadow: highlight
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.20),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}