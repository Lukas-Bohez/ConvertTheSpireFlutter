import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:convert_the_spire_reborn/src/config/build_flags.dart';
import 'package:convert_the_spire_reborn/src/config/full_mode_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FullModeAccess secret toggle', () {
    test('starts in play mode, toggles on after 3x full, then toggles off after 3x full', () async {
      SharedPreferences.setMockInitialValues({});
      final access = FullModeAccess.instance;
      access.resetForTesting();

      await access.load();
      expect(access.isLimitedPlayMode, isTrue);
      expect(access.isUnlocked, isFalse);

      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.enabled);

      expect(access.isUnlocked, isTrue);
      expect(access.isLimitedPlayMode, isFalse);

      // Simulate app restart and verify persisted unlocked state.
      access.resetForTesting();
      await access.load();
      expect(access.isUnlocked, isTrue);
      expect(access.isLimitedPlayMode, isFalse);

      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.disabled);

      expect(access.isUnlocked, isFalse);
      expect(access.isLimitedPlayMode, isTrue);

      // Simulate another restart and verify persisted locked state.
      access.resetForTesting();
      await access.load();
      expect(access.isUnlocked, isFalse);
      expect(access.isLimitedPlayMode, isTrue);
    });

    test('resets streak when input is not full', () async {
      SharedPreferences.setMockInitialValues({});
      final access = FullModeAccess.instance;
      access.resetForTesting();
      await access.load();

      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('notfull'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.none);
      expect(await access.submitUnlockAttempt('full'), FullModeToggleState.enabled);
    });

    test('full toggle enables and disables conversion features', () async {
      SharedPreferences.setMockInitialValues({});
      final access = FullModeAccess.instance;
      access.resetForTesting();
      await access.load();

      expect(access.isLimitedPlayMode, isTrue);
      expect(isYouTubeConversionEnabledInCurrentBuild, isFalse);
      expect(isTabVisibleInCurrentBuild(9), isFalse);

      await access.submitUnlockAttempt('full');
      await access.submitUnlockAttempt('full');
      final enableState = await access.submitUnlockAttempt('full');
      expect(enableState, FullModeToggleState.enabled);

      expect(access.isLimitedPlayMode, isFalse);
      expect(isYouTubeConversionEnabledInCurrentBuild, isTrue);
      expect(isTabVisibleInCurrentBuild(9), isTrue);

      await access.submitUnlockAttempt('full');
      await access.submitUnlockAttempt('full');
      final disableState = await access.submitUnlockAttempt('full');
      expect(disableState, FullModeToggleState.disabled);

      expect(access.isLimitedPlayMode, isTrue);
      expect(isYouTubeConversionEnabledInCurrentBuild, isFalse);
      expect(isTabVisibleInCurrentBuild(9), isFalse);
    });
  });
}
