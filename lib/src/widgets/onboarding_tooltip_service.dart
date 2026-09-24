import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/l10n.dart';

/// Manages progressive onboarding tooltips.
///
/// Steps:
///  0 → First launch: tooltip on search bar ("Start here.")
///  1 → After first search: tooltip on URL bar
///  2 → First visit to each new screen: dismissible banner
///  3 → First queue open: tooltip on queue area
///  4 → Done (all steps seen)
class OnboardingTooltipService {
  static const _stepKey = 'onboarding_step';
  static const _visitedScreensKey = 'onboarding_visited_screens';

  int _step = 0;
  Set<String> _visitedScreens = {};
  SharedPreferences? _prefs;

  int get step => _step;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _step = _prefs!.getInt(_stepKey) ?? 0;
      _visitedScreens =
          (_prefs!.getStringList(_visitedScreensKey) ?? []).toSet();
    } catch (_) {
      _prefs = null;
      _step = 0;
      _visitedScreens = {};
    }
  }

  Future<void> advanceTo(int newStep) async {
    if (newStep <= _step) return;
    _step = newStep;
    await _prefs?.setInt(_stepKey, _step);
  }

  bool hasVisitedScreen(String route) => _visitedScreens.contains(route);

  Future<void> markScreenVisited(String route) async {
    _visitedScreens.add(route);
    await _prefs?.setStringList(_visitedScreensKey, _visitedScreens.toList());
  }

  Future<void> reset() async {
    _step = 0;
    _visitedScreens = {};
    await _prefs?.setInt(_stepKey, 0);
    await _prefs?.setStringList(_visitedScreensKey, []);
  }

  /// Description shown as a banner on the first visit to [route], in the
  /// app's language, or null for screens without one.
  static String? screenDescription(AppLocalizations l, String route) {
    return switch (route) {
      'search.tab' => l.bannerSearch,
      'multisearch.tab' => l.bannerMultiSearch,
      'browser.tab' => l.bannerBrowser,
      'queue.tab' => l.bannerQueue,
      'playlists.tab' => l.bannerPlaylists,
      'bulkimport.tab' => l.bannerBulkImport,
      'stats.tab' => l.bannerStats,
      'settings.tab' => l.bannerSettings,
      'support.tab' => l.bannerSupport,
      'convert.tab' => l.bannerConvert,
      'logs.tab' => l.bannerLogs,
      'guide.tab' => l.bannerGuide,
      'player.tab' => l.bannerPlayer,
      _ => null,
    };
  }
}

/// A small dismissible banner shown at the top of a screen on first visit.
class OnboardingBanner extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const OnboardingBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  @override
  State<OnboardingBanner> createState() => _OnboardingBannerState();
}

class _OnboardingBannerState extends State<OnboardingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _opacity = Tween(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    _ctrl.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          border: Border(
            bottom: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.lightbulb_outline, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.message,
                style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer),
              ),
            ),
            InkWell(
              onTap: _dismiss,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child:
                    Icon(Icons.close, size: 16, color: cs.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
