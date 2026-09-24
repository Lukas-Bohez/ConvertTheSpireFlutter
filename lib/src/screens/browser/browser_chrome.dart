import 'package:flutter/material.dart';

/// Chrome colours shared by the browser toolbar and the tab switcher.
///
/// Incognito used to be a hard-coded dark purple, which ignored the support
/// colour the user picked (issue #7). It now blends the scheme's primary over
/// a dark base: still unmistakably "incognito", but tinted by their colour.
Color incognitoSurface(ColorScheme scheme) => Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.22),
      const Color(0xFF14141C),
    );

/// Foreground colour that stays readable on [incognitoSurface].
const Color onIncognitoSurface = Colors.white;
