import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const bool _kPlayStoreBuild = bool.fromEnvironment(
  'PLAY_STORE_BUILD',
  defaultValue: true,
);

enum FullModeToggleState {
  none,
  enabled,
  disabled,
}

class FullModeAccess extends ChangeNotifier {
  FullModeAccess._();

  static final FullModeAccess instance = FullModeAccess._();

  static const String _prefKey = 'full_mode_unlocked';
  static final String _unlockCode = String.fromCharCodes(
    <int>[70, 117, 108, 108],
  ).toLowerCase();

  bool _loaded = false;
  bool _isUnlocked = false;
  int _unlockAttempts = 0;

  bool get isUnlocked => _isUnlocked;

  bool get isLimitedPlayMode => _kPlayStoreBuild && !_isUnlocked;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _isUnlocked = prefs.getBool(_prefKey) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<FullModeToggleState> submitUnlockAttempt(String input) async {
    if (!_kPlayStoreBuild) return FullModeToggleState.none;

    if (input.trim().toLowerCase() == _unlockCode) {
      _unlockAttempts += 1;
      if (_unlockAttempts >= 3) {
        final wasUnlocked = _isUnlocked;
        if (wasUnlocked) {
          await _deactivateFullMode();
        } else {
          await _activateFullMode();
        }
        _unlockAttempts = 0;
        return wasUnlocked
            ? FullModeToggleState.disabled
            : FullModeToggleState.enabled;
      }
      return FullModeToggleState.none;
    }

    _unlockAttempts = 0;
    return FullModeToggleState.none;
  }

  Future<void> _activateFullMode() async {
    _isUnlocked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    notifyListeners();
  }

  Future<void> _deactivateFullMode() async {
    _isUnlocked = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
    notifyListeners();
  }
}
