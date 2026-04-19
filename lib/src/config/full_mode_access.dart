import 'package:flutter/foundation.dart';

const bool _kPlayStoreBuild = bool.fromEnvironment(
  'PLAY_STORE_BUILD',
  defaultValue: false,
);

enum FullModeToggleState {
  none,
  enabled,
  disabled,
}

class FullModeAccess extends ChangeNotifier {
  FullModeAccess._();

  static final FullModeAccess instance = FullModeAccess._();

  bool _loaded = false;
  bool _isUnlocked = false;

  bool get isUnlocked => _isUnlocked;

  bool get isLimitedPlayMode => _kPlayStoreBuild;

  Future<void> load() async {
    if (_loaded) return;
    _isUnlocked = !_kPlayStoreBuild;
    _loaded = true;
    notifyListeners();
  }

  Future<FullModeToggleState> submitUnlockAttempt(String input) async {
    return FullModeToggleState.none;
  }

  @visibleForTesting
  void resetForTesting() {
    _loaded = false;
    _isUnlocked = !_kPlayStoreBuild;
  }
}
