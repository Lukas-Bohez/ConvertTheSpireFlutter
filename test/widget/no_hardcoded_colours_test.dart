import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the support colour.
///
/// The player used to paint its bar, sliders and progress indicators with a
/// hard-coded blue, so the colour the user picked simply never showed up there
/// (issue #7). Screens and widgets take their colours from the active
/// ColorScheme; anything that genuinely cannot is listed below, with a reason.
void main() {
  /// Files allowed to name a colour directly, and why.
  const allowed = <String, String>{
    // The reward palette IS a list of literal colours - that is its content.
    'lib/src/features/colour_rewards/': 'the colour palette itself',
    // Onboarding paints its own branded gradients before a theme is chosen.
    'lib/src/screens/onboarding_screen.dart': 'branded onboarding artwork',
    // Incognito needs a dark base to blend the user's colour over.
    'lib/src/screens/browser/browser_chrome.dart': 'incognito base tone',
    // Runs from ErrorWidget.builder, which can fire outside any Theme.
    'lib/src/widgets/app_error_screen.dart': 'renders without a Theme',
  };

  bool isAllowed(String path) {
    final normalised = path.replaceAll(r'\', '/');
    return allowed.keys.any(normalised.contains);
  }

  /// Accent-like literals. Semantic status colours (green, orange, red) are
  /// deliberately not covered: those mean "ok" and "problem", not "brand".
  final pattern =
      RegExp(r'Color\(0x|Colors\.blue|Colors\.indigo|Colors\.purple');

  List<File> dartFilesUnder(String dir) {
    final directory = Directory(dir);
    if (!directory.existsSync()) return const [];
    return directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  test('screens and widgets take their accent from the theme', () {
    final offenders = <String>[];

    for (final dir in ['lib/src/screens', 'lib/src/widgets']) {
      for (final file in dartFilesUnder(dir)) {
        if (isAllowed(file.path)) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (pattern.hasMatch(lines[i])) {
            offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Use Theme.of(context).colorScheme instead, so the support '
          'colour applies. If a literal is genuinely unavoidable, add the '
          'file to the allow list in this test with a reason.\n'
          '${offenders.join('\n')}',
    );
  });

  test('the allow list only names files that exist', () {
    for (final entry in allowed.entries) {
      final path = entry.key;
      final exists = path.endsWith('/')
          ? Directory(path).existsSync()
          : File(path).existsSync();
      expect(exists, isTrue,
          reason: '$path is allow-listed (${entry.value}) but is not there; '
              'remove the entry.');
    }
  });
}
