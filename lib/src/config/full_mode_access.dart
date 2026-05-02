import 'package:flutter/foundation.dart';

enum FullModeToggleState {
  none,
  enabled,
  disabled,
}

class FullModeAccess extends ChangeNotifier {
  FullModeAccess._();

  static final FullModeAccess instance = FullModeAccess._();

  bool _loaded = false;

  bool get isUnlocked => true;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    notifyListeners();
  }

  Future<FullModeToggleState> submitUnlockAttempt(String input) async {
    return FullModeToggleState.none;
  }

  @visibleForTesting
  void resetForTesting() {
    _loaded = false;
  }
}
