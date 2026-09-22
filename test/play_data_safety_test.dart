import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Play Data Safety declaration against silent drift.
///
/// Version code 1286 was rejected by Google Play because the app transmitted
/// the advertising ID (via AdMob) without declaring "Device or other IDs" on
/// the Data Safety form. These tests pin the arrangement that declaration
/// describes, so a change that would invalidate it fails here instead of in
/// review a week later.
///
/// The declaration itself lives in docs/publishing/play-data-safety.md.
void main() {
  String read(String path) => File(path).readAsStringSync();

  const adIdPermission = 'com.google.android.gms.permission.AD_ID';
  const mainManifest = 'android/app/src/main/AndroidManifest.xml';
  const playManifest = 'android/app/src/play/AndroidManifest.xml';
  const fullManifest = 'android/app/src/full/AndroidManifest.xml';

  group('advertising ID permission', () {
    test('is declared in the play flavor, which serves AdMob ads', () {
      expect(read(playManifest), contains(adIdPermission));
    });

    test('is NOT in the shared manifest, so it cannot leak into other flavors',
        () {
      // A bare declaration here would apply to the ad-free GitHub build too,
      // making its permission list inaccurate.
      final main = read(mainManifest);
      final declared = RegExp(
              r'<uses-permission[^>]*' + RegExp.escape(adIdPermission))
          .hasMatch(main);
      expect(declared, isFalse,
          reason: 'AD_ID must be declared only in src/play/AndroidManifest.xml');
    });

    test('the ad-free full flavor explicitly removes it', () {
      // Deleting the declaration from src/main is NOT enough: the
      // google_mobile_ads AAR merges AD_ID in from its own manifest, so the
      // ad-free build only loses it via an explicit tools:node="remove".
      final full = read(fullManifest);
      expect(full, contains(adIdPermission));
      expect(full, contains('ACCESS_ADSERVICES_AD_ID'));
      expect(RegExp(r'tools:node="remove"').allMatches(full).length,
          greaterThanOrEqualTo(2),
          reason: 'both advertising-ID permissions must be removed by name');
    });

    test('merged manifests agree, when a build has produced them', () {
      // Source files only describe intent. This checks what actually ships.
      // Skipped silently on a clean checkout with no build output.
      String merged(String flavor, String task) =>
          'build/app/intermediates/merged_manifests/${flavor}Release/'
          'process${task}ReleaseManifest/AndroidManifest.xml';
      final play = File(merged('play', 'Play'));
      final full = File(merged('full', 'Full'));
      if (!play.existsSync() || !full.existsSync()) return;

      final declaration =
          RegExp('<uses-permission[^>]*' + RegExp.escape(adIdPermission));
      expect(declaration.hasMatch(play.readAsStringSync()), isTrue,
          reason: 'the Play build serves ads and needs the advertising ID');
      expect(declaration.hasMatch(full.readAsStringSync()), isFalse,
          reason: 'the GitHub build is ad-free and must not request it');
    });
  });

  group('data safety documentation', () {
    test('the declaration document exists', () {
      expect(File('docs/publishing/play-data-safety.md').existsSync(), isTrue,
          reason: 'the Data Safety answers must stay written down');
    });

    test('it names the data type Play requires for AdMob', () {
      expect(read('docs/publishing/play-data-safety.md'),
          contains('Device or other IDs'));
    });
  });

  group('no undeclared data-collecting SDKs crept in', () {
    // Anything added here also has to be added to the Data Safety form, so a
    // new dependency should fail this test until that has been thought about.
    const knownCollectors = ['google_mobile_ads'];
    const collectorPatterns = [
      'firebase_analytics',
      'firebase_crashlytics',
      'sentry_flutter',
      'amplitude',
      'mixpanel',
      'posthog',
      'appsflyer',
      'onesignal',
      'facebook_app_events',
      'segment',
    ];

    test('pubspec has no analytics or attribution SDK', () {
      final pubspec = read('pubspec.yaml');
      for (final name in collectorPatterns) {
        expect(pubspec.contains('$name:'), isFalse,
            reason: '$name collects user data - update '
                'docs/publishing/play-data-safety.md and the Play Console form '
                'before allowing it');
      }
    });

    test('AdMob is still the only declared collector', () {
      expect(read('pubspec.yaml'), contains(knownCollectors.first));
    });
  });
}
