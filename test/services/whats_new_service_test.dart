import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/whats_new_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the "what's new" parsing.
///
/// Releases shipped with nothing telling people what changed (issue #7). The
/// notes come from CHANGELOG.md, which is already maintained, so these tests
/// mostly protect against the heading format drifting.
void main() {
  const changelog = '''
# Changelog

## 14.3.1+1295 — Watch Together polish

### Fixed

- Seeking now reaches the room immediately.
- Local build logs no longer clutter the repository root.

## 14.3.0+1294 — Userscripts in the browser

### Added

- Userscripts.
''';

  group('entryFor', () {
    test('finds a version and splits off its title', () {
      final entry = WhatsNewService.entryFor(changelog, '14.3.1');

      expect(entry, isNotNull);
      expect(entry!.version, '14.3.1');
      expect(entry.title, 'Watch Together polish');
      expect(entry.body, contains('Seeking now reaches the room'));
    });

    test('stops at the next release heading', () {
      final entry = WhatsNewService.entryFor(changelog, '14.3.1');

      expect(entry!.body, isNot(contains('Userscripts')));
    });

    test('a build number or leading v in the query is ignored', () {
      expect(WhatsNewService.entryFor(changelog, '14.3.1+1295')?.title,
          'Watch Together polish');
      expect(WhatsNewService.entryFor(changelog, 'v14.3.1')?.title,
          'Watch Together polish');
    });

    test('an older version still resolves', () {
      final entry = WhatsNewService.entryFor(changelog, '14.3.0');

      expect(entry!.title, 'Userscripts in the browser');
      expect(entry.body, contains('Userscripts.'));
    });

    test('an unknown version has no entry', () {
      expect(WhatsNewService.entryFor(changelog, '99.0.0'), isNull);
      expect(WhatsNewService.entryFor(changelog, ''), isNull);
    });

    test('a heading with no title still parses', () {
      final entry =
          WhatsNewService.entryFor('## 1.2.3\n\n- Something\n', '1.2.3');

      expect(entry, isNotNull);
      expect(entry!.title, isEmpty);
      expect(entry.body, contains('Something'));
    });
  });

  group('the real changelog', () {
    test('has an entry for the version in pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(pubspec)
          ?.group(1);
      expect(version, isNotNull, reason: 'pubspec has no version');

      final entry = WhatsNewService.entryFor(
          File('CHANGELOG.md').readAsStringSync(), version!);

      expect(entry, isNotNull,
          reason: 'CHANGELOG.md has no section for $version, so the release '
              'would ship with nothing to show. Add one before releasing.');
    });

    test('is bundled, or the dialog would always be empty', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(pubspec, contains(WhatsNewService.changelogAsset));
    });
  });
}
