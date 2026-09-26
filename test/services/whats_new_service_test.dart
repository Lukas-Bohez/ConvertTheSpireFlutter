import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/whats_new_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guards the "what's new" parsing.
///
/// Releases shipped with nothing telling people what changed (issue #7). The
/// notes come from CHANGELOG.md, which is already maintained, so these tests
/// mostly protect against the heading format drifting.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('entrySince', () {
    const skipped = '''
## 14.10.0 — Ten

- Ten.

## 14.9.0 — Nine

- Nine.

## 14.4.1+1297 — Starts again

- Fixed the spinner.

## 14.4.0+1296 — Extensions

- Extensions.

## 14.3.1+1295 — Polish

- Polish.
''';

    List<String> earlierOf(WhatsNewEntry? entry) =>
        entry!.earlier.map((e) => e.version).toList();

    test('carries every release after the last one seen, newest first', () {
      final entry =
          WhatsNewService.entrySince(skipped, '14.4.1', lastSeen: '14.3.1');

      expect(entry!.version, '14.4.1');
      expect(entry.body, contains('Fixed the spinner'));
      expect(earlierOf(entry), ['14.4.0']);
      expect(entry.earlier.single.title, 'Extensions');
    });

    test('nothing skipped means nothing extra', () {
      final entry =
          WhatsNewService.entrySince(skipped, '14.4.1', lastSeen: '14.4.0');

      expect(earlierOf(entry), isEmpty);
    });

    test('with no record, everything since the dialog arrived is new', () {
      final entry = WhatsNewService.entrySince(skipped, '14.4.1');

      expect(earlierOf(entry), ['14.4.0'],
          reason: 'releases before ${WhatsNewService.firstVersionWithDialog} '
              'predate the dialog, and the person saw them in the app');
    });

    test('versions compare as numbers, not text', () {
      final entry =
          WhatsNewService.entrySince(skipped, '14.10.0', lastSeen: '14.4.1');

      expect(earlierOf(entry), ['14.9.0']);
    });

    test('never more than ${WhatsNewService.maxEntries} releases', () {
      final many = StringBuffer();
      for (var minor = 30; minor >= 10; minor--) {
        many.writeln('## 15.$minor.0 — Release $minor\n\n- Item.\n');
      }
      final entry = WhatsNewService.entrySince(many.toString(), '15.30.0',
          lastSeen: '15.10.0');

      expect(entry!.earlier.length, WhatsNewService.maxEntries - 1);
      expect(entry.earlier.first.version, '15.29.0',
          reason: 'the most recent releases are the ones kept');
    });

    test('an unknown current version has no entry', () {
      expect(WhatsNewService.entrySince(skipped, '99.0.0', lastSeen: '1.0.0'),
          isNull);
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

    test('someone who skipped releases hears about each one they missed', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(pubspec)!
          .group(1)!;
      final changelog = File('CHANGELOG.md').readAsStringSync();
      final all =
          WhatsNewService.entries(changelog).map((e) => e.version).toList();

      // Coming from a few releases back (as everyone did who skipped 14.4.0,
      // which never got past its loading screen): every release since then
      // is shown, newest first, up to maxEntries.
      final skipped = WhatsNewService.maxEntries - 1;
      final entry = WhatsNewService.entrySince(changelog, version,
          lastSeen: all[skipped]);

      expect([entry!.version, ...entry.earlier.map((e) => e.version)],
          all.sublist(0, skipped));
    });

    test('is bundled, or the dialog would always be empty', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(pubspec, contains(WhatsNewService.changelogAsset));
    });
  });

  group('pendingEntry', () {
    String pubspecVersion() {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      return RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(pubspec)!
          .group(1)!;
    }

    test('a first install shows nothing and remembers the version', () async {
      SharedPreferences.setMockInitialValues({});
      final version = pubspecVersion();

      expect(await WhatsNewService.instance.pendingEntry(version), isNull);
      expect(
        await WhatsNewService.instance
            .pendingEntry(version, freshInstall: false),
        isNull,
        reason: 'the version was recorded on the first call',
      );
    });

    test('an update from a version without this dialog shows the notes',
        () async {
      SharedPreferences.setMockInitialValues({});
      final version = pubspecVersion();

      final entry = await WhatsNewService.instance
          .pendingEntry(version, freshInstall: false);

      expect(entry, isNotNull,
          reason: 'people updating from before this dialog existed should '
              'still see what this release changed');
    });

    test('notes already shown are not shown again', () async {
      SharedPreferences.setMockInitialValues({});
      final version = pubspecVersion();
      await WhatsNewService.instance.markShown(version);

      expect(
        await WhatsNewService.instance
            .pendingEntry(version, freshInstall: false),
        isNull,
      );
    });
  });
}
