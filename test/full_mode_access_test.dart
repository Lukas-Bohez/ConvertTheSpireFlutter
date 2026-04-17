import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  });
}
