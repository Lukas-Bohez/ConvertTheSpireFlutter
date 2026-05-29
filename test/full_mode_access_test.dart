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

      final expectedTitle = kPlayStoreBuild ? 'BitPlayer' : 'Convert The Spire Reborn';
      final expectedSubtitle =
          kPlayStoreBuild ? 'BitPlayer — media & torrents' : 'Convert The Spire Reborn — media & torrents';
      final expectedFolderName = kPlayStoreBuild ? 'BitPlayer' : 'ConvertTheSpireReborn';

      expect(getAppTitle(), expectedTitle);
      expect(getAppSubtitle(), expectedSubtitle);
      expect(getDefaultDownloadFolderName(), expectedFolderName);
    });
  });
}
