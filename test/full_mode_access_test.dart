import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:convert_the_spire_reborn/src/config/build_flags.dart';
import 'package:convert_the_spire_reborn/src/config/full_mode_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FullModeAccess fixed mode', () {
    test('access is always unlocked and unlock attempts are ignored', () async {
      SharedPreferences.setMockInitialValues({});
      final access = FullModeAccess.instance;
      access.resetForTesting();

      await access.load();
      expect(access.isUnlocked, isTrue);

      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(access.isUnlocked, isTrue);
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
      expect(access.isUnlocked, isTrue);
      expect(isYouTubeConversionEnabledInCurrentBuild, equals(!kPlayStoreBuild));
      expect(isTabVisibleInCurrentBuild(9), isFalse);
    });

    test('branding is consistent across builds', () async {
      SharedPreferences.setMockInitialValues({});
      final access = FullModeAccess.instance;
      access.resetForTesting();
      await access.load();

      expect(getAppTitle(), 'Convert the Spire Reborn');
      expect(getAppSubtitle(), 'Torrent manager & media toolkit');
      expect(getDefaultDownloadFolderName(), 'ConvertTheSpireReborn');
    });
  });
}
