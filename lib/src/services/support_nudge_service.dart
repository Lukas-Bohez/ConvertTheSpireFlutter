import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_flags.dart';

/// When Home shows a small card asking for a donation (issue #41).
///
/// In the GitHub and Microsoft Store versions donations are the only
/// income: no ads, nothing to buy. The card is no popup and asks only from
/// someone the app has served for a while: ten starts and five things that
/// went well (a finished download, a video played). After a donation link
/// it stays away four months, after "Not now" six weeks, and "Don't show
/// again" is for good. The Play version earns from its ads instead.
class SupportNudgeService extends ChangeNotifier {
  SupportNudgeService._();

  static final SupportNudgeService instance = SupportNudgeService._();

  static const _launchesKey = 'support_nudge_launches';
  static const _successesKey = 'support_nudge_successes';
  static const _snoozedUntilKey = 'support_nudge_snoozed_until';
  static const _neverKey = 'support_nudge_never';

  static const minLaunches = 10;
  static const minSuccesses = 5;
  static const afterDonating = Duration(days: 120);
  static const afterNotNow = Duration(days: 45);

  @visibleForTesting
  static bool Function() enabledInBuild = () => !kPlayStoreBuild;

  bool _show = false;

  /// Whether Home shows the card now.
  bool get show => _show;

  /// Counts a start of the app; call once per launch.
  Future<void> trackLaunch({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_launchesKey, (prefs.getInt(_launchesKey) ?? 0) + 1);
    await _update(prefs, now ?? DateTime.now());
  }

  /// Counts something that went well.
  Future<void> recordSuccess({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _successesKey, (prefs.getInt(_successesKey) ?? 0) + 1);
    await _update(prefs, now ?? DateTime.now());
  }

  /// A donation link was opened.
  Future<void> donated({DateTime? now}) =>
      _snooze((now ?? DateTime.now()).add(afterDonating));

  Future<void> notNow({DateTime? now}) =>
      _snooze((now ?? DateTime.now()).add(afterNotNow));

  Future<void> never() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_neverKey, true);
    _set(false);
  }

  Future<void> _snooze(DateTime until) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_snoozedUntilKey, until.millisecondsSinceEpoch);
    _set(false);
  }

  Future<void> _update(SharedPreferences prefs, DateTime now) async {
    final snoozedUntil = prefs.getInt(_snoozedUntilKey) ?? 0;
    _set(enabledInBuild() &&
        !(prefs.getBool(_neverKey) ?? false) &&
        (prefs.getInt(_launchesKey) ?? 0) >= minLaunches &&
        (prefs.getInt(_successesKey) ?? 0) >= minSuccesses &&
        now.millisecondsSinceEpoch >= snoozedUntil);
  }

  void _set(bool show) {
    if (_show == show) return;
    _show = show;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTesting() => _show = false;
}
