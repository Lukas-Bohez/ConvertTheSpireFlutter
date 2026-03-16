import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    _prefs = await SharedPreferences.getInstance();
    _step = _prefs!.getInt(_stepKey) ?? 0;
    _visitedScreens = (_prefs!.getStringList(_visitedScreensKey) ?? []).toSet();
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

  /// Descriptions shown as a banner on first visit to each screen.
  static const Map<String, String> screenDescriptions = {
    'search.tab': 'Download audio or video from any YouTube URL.',
    'multisearch.tab':
        'Search YouTube & SoundCloud simultaneously and add results to your queue.',
    'browser.tab':
        'Browse the web with built-in ad blocking and video detection.',
    'queue.tab': 'Track and manage your downloads here.',
    'playlists.tab':
        'Load YouTube playlists, compare with local folders, and download missing tracks.',
    'bulkimport.tab':
        'Paste a list of tracks (Artist - Title) to bulk-download them.',
    'stats.tab': 'View your download statistics and trends.',
    'settings.tab': 'Configure download directory, format, quality, and tools.',
    'support.tab':
        'Support the project via donations or by contributing feedback.',
    'convert.tab':
        'Convert audio and video files between formats using FFmpeg.',
    'logs.tab': 'View the activity log for debugging and monitoring.',
    'guide.tab': 'Documentation, tips, and troubleshooting.',
    'player.tab':
        'Play your downloaded music and videos with the built-in media player.',
  };
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
