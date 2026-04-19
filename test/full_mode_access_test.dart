import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:convert_the_spire_reborn/src/config/build_flags.dart';
import 'package:convert_the_spire_reborn/src/config/full_mode_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FullModeAccess fixed mode', () {
    test('play build remains limited and unlock attempts are ignored', () async {
      SharedPreferences.setMockInitialValues({});
      final access = FullModeAccess.instance;
      access.resetForTesting();

      await access.load();
      expect(access.isLimitedPlayMode, equals(kPlayStoreBuild));
      expect(access.isUnlocked, equals(!kPlayStoreBuild));

      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(access.isUnlocked, equals(!kPlayStoreBuild));
      expect(access.isLimitedPlayMode, equals(kPlayStoreBuild));
    });

    test('unlock attempts never affect build feature gates', () async {
      SharedPreferences.setMockInitialValues({});
      final access = FullModeAccess.instance;
      access.resetForTesting();
      await access.load();

      expect(isYouTubeConversionEnabledInCurrentBuild, equals(!kPlayStoreBuild));
      expect(isTabVisibleInCurrentBuild(9), isFalse);

      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('notfull'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(access.isLimitedPlayMode, equals(kPlayStoreBuild));
      expect(isYouTubeConversionEnabledInCurrentBuild, equals(!kPlayStoreBuild));
      expect(isTabVisibleInCurrentBuild(9), isFalse);
    });

    test('branding follows fixed build mode', () async {
      SharedPreferences.setMockInitialValues({});
      final access = FullModeAccess.instance;
      access.resetForTesting();
      await access.load();

      if (kPlayStoreBuild) {
        expect(getAppTitle(), 'Bitplayer');
        expect(getAppSubtitle(), 'Torrent vault & media hub');
        expect(getDefaultDownloadFolderName(), 'Bitplayer');
      } else {
        expect(getAppTitle(), 'Convert the Spire Reborn');
        expect(getAppSubtitle(), 'Torrent manager & media toolkit');
        expect(getDefaultDownloadFolderName(), 'ConvertTheSpireReborn');
      }
    });
  });
}
