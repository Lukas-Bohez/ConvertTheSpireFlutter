import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/build_flags.dart';
import '../theme/motion_tokens.dart';
import '../widgets/tv_safe_area.dart';

/// A multi-page onboarding flow that introduces the app's features.
///
/// Used in two places:
///  * Automatically on first launch - the caller marks "seenOnboarding" when
///    [onFinish] fires.
///  * Manually from the Guide screen via a button.
///
/// Redesigned 2026-08 to cut the flow from 14 pages down to 5 by grouping
/// related features onto shared pages instead of one page per feature, and
/// to keep every page's content clear of a TV's overscan area via
/// [TvSafeArea]. See ONBOARDING_UX_REDESIGN.md for the full write-up and
/// the old-page -> new-page content mapping. Pages are no longer dropped
/// wholesale for the Play Store build the way they used to be - see
/// `_buildPages()` below - only the bullets inside a page that don't apply
/// to the current build/platform are hidden, so every flavour still gets
/// all 5 pages.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinish;
  final ValueChanged<ThemeMode>? onThemeChanged;
  final ThemeMode themeMode;

  const OnboardingScreen({
    required this.onFinish,
    this.onThemeChanged,
    this.themeMode = ThemeMode.system,
    super.key,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _controller;
  late final AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late ThemeMode _themeMode;
  late final List<_OnboardingPage> _pages;
  int _page = 0;

  // --- Page content --------------------------------------------------------

  static List<_OnboardingPage> _buildPages() => <_OnboardingPage>[
        // Welcome (was page 1 of 14: Welcome)
        _OnboardingPage(
          icon: Icons.download_rounded,
          title: 'Welcome',
          detail: kPlayStoreBuild
              ? '${getAppTitle()} is a torrent vault and media hub. Add '
                  'magnet links and .torrent files, manage downloads, and '
                  'keep everything organized from one app.'
              : '${getAppTitle()} is a cross-platform torrent and media '
                  'toolkit. Add magnet links and .torrent files, manage '
                  'downloads, convert formats, cast to your TV, and more '
                  '- all from one app.',
          color: const Color(0xFF00897B),
          preview: const _WelcomePreview(),
        ),

        // Find & Add Content (was: Supported Sources, Search,
        // Multi-Search, Browser, Bulk Import - 5 of the old 14 pages)
        _OnboardingPage(
          icon: Icons.travel_explore_rounded,
          title: 'Find & Add Content',
          detail: kPlayStoreBuild
              ? 'Browse the web in the built-in view and open magnet or '
                  'torrent links directly, without leaving the app.'
              : 'Add torrent files, magnet links, browser links, or local '
                  'files. Search by keyword, compare results from more '
                  'than one source, browse the web for links, or paste a '
                  'whole list to import at once.',
          color: const Color(0xFF6C63FF),
          preview: _FeatureListPreview(items: [
            _FeatureItem(
              icon: Icons.search_rounded,
              color: const Color(0xFF6C63FF),
              label: 'Search',
              blurb: 'Preview a result before you download it',
              visible: !kPlayStoreBuild,
            ),
            _FeatureItem(
              icon: Icons.travel_explore_rounded,
              color: const Color(0xFF43CFBB),
              label: 'Multi-Search',
              blurb: 'Compare results from several sources at once',
              visible: !kPlayStoreBuild,
            ),
            const _FeatureItem(
              icon: Icons.open_in_browser_rounded,
              color: Color(0xFF4A90D9),
              label: 'Browser',
              blurb: 'Browse the web and open links in-app',
            ),
            _FeatureItem(
              icon: Icons.upload_file_rounded,
              color: const Color(0xFF5BA85A),
              label: 'Bulk Import',
              blurb: 'Paste or import a list of links at once',
              visible: !kPlayStoreBuild,
            ),
          ]),
        ),

        // Manage Your Downloads (was: Queue, Stats)
        _OnboardingPage(
          icon: Icons.queue_music_rounded,
          title: 'Manage Your Downloads',
          detail: kPlayStoreBuild
              ? 'Manage your downloads: start, retry, or cancel, and find '
                  'finished files in your file manager.'
              : 'Manage your downloads: start, retry, cancel, or cast to '
                  'your TV. Check totals, success rate, and trends any '
                  'time in Stats.',
          color: const Color(0xFFE07B54),
          preview: _FeatureListPreview(items: [
            const _FeatureItem(
              icon: Icons.queue_music_rounded,
              color: Color(0xFFE07B54),
              label: 'Queue',
              blurb: 'Start, retry, cancel, and track status',
            ),
            _FeatureItem(
              icon: Icons.bar_chart_rounded,
              color: const Color(0xFFD4A017),
              label: 'Stats',
              blurb: 'Totals, success rate, and trends over time',
              visible: !kPlayStoreBuild,
            ),
          ]),
        ),

        // Play, Convert & Customize (was: Player, Convert, Settings)
        _OnboardingPage(
          icon: Icons.tune_rounded,
          title: 'Play, Convert & Customize',
          // Convert tab is hidden on all Android builds, not just Play
          // Store - see isTabVisibleInCurrentBuild(9) in build_flags.dart.
          // The old onboarding described Convert unconditionally, so
          // Android users were being told about a feature they had no way
          // to reach. Tying this page to the same flag fixes that.
          detail: isTabVisibleInCurrentBuild(9)
              ? 'Play your files in the built-in player, convert between '
                  'formats with FFmpeg, and set folders, defaults, and '
                  'appearance in Settings.'
              : 'Play your files in the built-in player, and set folders, '
                  'format defaults, and appearance in Settings.',
          color: const Color(0xFF7E57C2),
          preview: _FeatureListPreview(items: [
            const _FeatureItem(
              icon: Icons.music_note_rounded,
              color: Color(0xFF7E57C2),
              label: 'Player',
              blurb: 'Playback, shuffle, repeat, and a simple library',
            ),
            _FeatureItem(
              icon: Icons.transform_rounded,
              color: const Color(0xFFE57373),
              label: 'Convert',
              blurb: 'Convert audio/video between formats with FFmpeg',
              visible: isTabVisibleInCurrentBuild(9),
            ),
            const _FeatureItem(
              icon: Icons.settings_rounded,
              color: Color(0xFF607D8B),
              label: 'Settings',
              blurb: 'Folders, format defaults, retry behaviour, and more',
            ),
          ]),
        ),

        // Help & Support (was: Guide, Logs, Support Us)
        _OnboardingPage(
          icon: Icons.favorite_rounded,
          title: 'Help & Support',
          detail: kPlayStoreBuild
              ? 'Revisit the Guide any time you need a refresher, and '
                  'help keep the project going with a donation.'
              : 'Revisit the Guide any time, check the internal Logs if '
                  'something goes wrong, and help keep the project '
                  'open-source and ad-free with a donation.',
          color: const Color(0xFFE91E63),
          preview: const _HelpSupportPreview(),
        ),
      ];

  // --- Lifecycle ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _pages = _buildPages();
    _themeMode = widget.themeMode;
    _controller = PageController();
        _animController = AnimationController(
      vsync: this,
      duration: MotionTokens.standard,
    );
    _setupAnimations();

    // Delay the initial animation until after the first frame is rendered to
    // avoid blocking the UI thread during initial layout on slower devices.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animController.forward();
    });
  }

  void _setupAnimations() {
    // Use a subtle fade (0.92 -> 1.0) instead of full fade-from-black to
    // avoid transient black flashes on slower mobile devices when pages are
    // rebuilt during fast swipes.
        _fadeAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(parent: _animController, curve: MotionTokens.enter));
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: MotionTokens.enter));
  }

  @override
  void dispose() {
    _controller.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _page = index);
    _animController.forward(from: 0);
  }

  void _next() {
    if (_page < _pages.length - 1) {
            _controller.nextPage(
        duration: MotionTokens.standard,
        curve: MotionTokens.standardCurve,
      );
    }
  }

  void _handleKeyboardAdvance() {
    if (_page < _pages.length - 1) {
      _next();
      return;
    }
    widget.onFinish();
  }

  void _back() {
    if (_page > 0) {
            _controller.previousPage(
        duration: MotionTokens.standard,
        curve: MotionTokens.standardCurve,
      );
    }
  }

  void _cycleTheme() {
    final next = switch (_themeMode) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    setState(() => _themeMode = next);
    widget.onThemeChanged?.call(next);
  }

  IconData get _themeIcon => switch (_themeMode) {
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
        ThemeMode.system => Icons.brightness_auto_rounded,
      };

  String get _themeLabel => switch (_themeMode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'Auto',
      };

  // --- Sub-builders -----------------------------------------------------

  // Replaces the old Scaffold(appBar: AppBar(...)). An AppBar sits outside
  // the body, so it never got the SafeArea/TvSafeArea protection below it -
  // on a TV the title and theme toggle could end up right in the overscan
  // strip. Building the title bar as ordinary body content means the same
  // TvSafeArea that protects the rest of the page protects this too.
  Widget _buildTitleBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              getAppTitle(),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          _buildThemeToggle(theme),
        ],
      ),
    );
  }

  Widget _buildProgressBar(ThemeData theme) {
    final progress = (_page + 1) / _pages.length;
    final pageColor = _pages[_page].color;
    final subtle = theme.colorScheme.onSurface.withValues(alpha: 0.45);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step ${_page + 1} of ${_pages.length}',
                style: theme.textTheme.labelMedium?.copyWith(color: subtle),
              ),
              Text(
                _pages[_page].title,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: pageColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: MotionTokens.standard,
              curve: MotionTokens.standardCurve,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(pageColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDots(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pages.length, (i) {
        final bool active = i == _page;
        return AnimatedContainer(
          duration: MotionTokens.standard,
          curve: MotionTokens.standardCurve,
          width: active ? 22 : 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: active
                ? _pages[_page].color
                : theme.colorScheme.onSurface.withValues(alpha: 0.18),
          ),
        );
      }),
    );
  }

  Widget _buildThemeToggle(ThemeData theme) {
    final pageColor = _pages[_page].color;
    return Tooltip(
      message: 'Theme: $_themeLabel \u2014 tap to cycle',
      child: InkWell(
        onTap: _cycleTheme,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: MotionTokens.quick,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: pageColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: pageColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_themeIcon, size: 16, color: pageColor),
              const SizedBox(width: 6),
              Text(
                _themeLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: pageColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(ThemeData theme) {
    final isFirst = _page == 0;
    final isLast = _page == _pages.length - 1;
    final pageColor = _pages[_page].color;
    final onSurface = theme.colorScheme.onSurface;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Back / Skip
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isFirst)
              TextButton.icon(
                key: const ValueKey('back'),
                onPressed: _back,
                style: TextButton.styleFrom(
                  foregroundColor: onSurface.withValues(alpha: 0.65),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 15),
                label: const Text(
                  'Back',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            if (!isLast)
              TextButton(
                key: const ValueKey('skip'),
                onPressed: widget.onFinish,
                style: TextButton.styleFrom(
                  foregroundColor: onSurface.withValues(alpha: 0.55),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
          ],
        ),
        // Next / Done
        AnimatedSwitcher(
          duration: MotionTokens.quick,
          child: isLast
              ? ElevatedButton.icon(
                  key: const ValueKey('done'),
                  onPressed: widget.onFinish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pageColor,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text("Let's Go!"),
                )
              : ElevatedButton.icon(
                  key: const ValueKey('next'),
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pageColor,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
                  label: const Text('Next'),
                ),
        ),
      ],
    );
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final squareSide = (screenWidth * 0.50).clamp(150.0, 280.0);

    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }

          switch (event.logicalKey) {
            case LogicalKeyboardKey.arrowRight:
            case LogicalKeyboardKey.enter:
            case LogicalKeyboardKey.numpadEnter:
            case LogicalKeyboardKey.select:
              _handleKeyboardAdvance();
              return KeyEventResult.handled;
            case LogicalKeyboardKey.arrowLeft:
              _back();
              return KeyEventResult.handled;
            default:
              return KeyEventResult.ignored;
          }
        },
        child: SafeArea(
          child: TvSafeArea(
            child: Column(
              children: [
                _buildTitleBar(theme),
                _buildProgressBar(theme),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: _onPageChanged,
                    children: List.generate(_pages.length, (index) {
                      final p = _pages[index];
                      return _KeepAlivePage(
                        key: ValueKey('onboarding_page_$index'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28.0,
                            vertical: 12,
                          ),
                          child: FadeTransition(
                            opacity: _fadeAnim,
                            child: SlideTransition(
                              position: _slideAnim,
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 8),
                                    Container(
                                      width: squareSide,
                                      height: squareSide,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            p.color.withValues(alpha: 0.18),
                                            p.color.withValues(alpha: 0.06),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(28),
                                        border: Border.all(
                                          color:
                                              p.color.withValues(alpha: 0.30),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: p.color
                                                .withValues(alpha: 0.15),
                                            blurRadius: 28,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        p.icon,
                                        size: squareSide * 0.42,
                                        color: p.color,
                                      ),
                                    ),
                                    if (p.preview != null) ...[
                                      const SizedBox(height: 20),
                                      p.preview!,
                                    ],
                                    const SizedBox(height: 28),
                                    Text(
                                      p.title,
                                      style: theme.textTheme.headlineMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: p.color,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      p.detail,
                                      textAlign: TextAlign.center,
                                      style:
                                          theme.textTheme.bodyLarge?.copyWith(
                                        height: 1.65,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.78),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                _buildDots(theme),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20.0, vertical: 8),
                  child: _buildControls(theme),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Data model --------------------------------------------------------------

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String detail;
  final Color color;
  final Widget? preview;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
    this.preview,
  });
}

/// One row inside a [_FeatureListPreview] card.
class _FeatureItem {
  final IconData icon;
  final Color color;
  final String label;
  final String blurb;

  /// Whether this row should be shown for the current build/platform.
  /// Defaults to true; pages set this per-item for features that aren't
  /// available in every flavour - e.g. Search is hidden in Play Store
  /// builds, Convert is hidden on Android.
  final bool visible;

  const _FeatureItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.blurb,
    this.visible = true,
  });
}

/// Keeps a page alive once it has been built, preventing transient black
/// flashes when the user rapidly swipes between pages.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child, super.key});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin<_KeepAlivePage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// --- Preview widgets -----------------------------------------------------

/// Welcome page - shows a brief feature overview.
class _WelcomePreview extends StatelessWidget {
  const _WelcomePreview();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDDDDD);

    final features = kPlayStoreBuild
        ? const [
            (Icons.download_rounded, 'Torrent downloads'),
            (Icons.folder_copy_rounded, 'Queue & library'),
            (Icons.favorite_outline, 'Support via donations'),
          ]
        : const [
            (Icons.download_rounded, 'Torrent downloads'),
            (Icons.transform_rounded, 'Format conversion'),
            (Icons.cast_rounded, 'DLNA / Cast to TV'),
            (Icons.favorite_outline, 'Support via donations'),
          ];

    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: features
            .map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(f.$1, size: 20, color: const Color(0xFF00897B)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

/// Compact card listing several related features - icon, label, and a
/// one-line blurb per row. Used on every page that groups more than one
/// of the old 14 pages together, so cutting the page count doesn't cut
/// any of the original information - it just no longer gets a whole
/// screen to itself.
class _FeatureListPreview extends StatelessWidget {
  final List<_FeatureItem> items;

  const _FeatureListPreview({required this.items});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDDDDD);
    final subtitle = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final visibleItems = items.where((i) => i.visible).toList();

    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: visibleItems
            .map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(item.icon, size: 18, color: item.color),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.label,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              item.blurb,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: subtitle),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

/// Help & Support page preview: Guide/Logs as feature rows, plus the
/// original donation card underneath.
class _HelpSupportPreview extends StatelessWidget {
  const _HelpSupportPreview();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FeatureListPreview(items: [
          const _FeatureItem(
            icon: Icons.menu_book_rounded,
            color: Color(0xFF26A69A),
            label: 'Guide',
            blurb: 'A help screen you can revisit any time',
          ),
          _FeatureItem(
            icon: Icons.list_alt_rounded,
            color: const Color(0xFF78909C),
            label: 'Logs',
            blurb: 'Inspect, copy, or clear the internal app log',
            visible: !kPlayStoreBuild,
          ),
        ]),
        const SizedBox(height: 12),
        const _SupportPreview(),
      ],
    );
  }
}

/// Support CTA preview shown on the last onboarding page.
class _SupportPreview extends StatelessWidget {
  const _SupportPreview();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDDDDD);
    const accent = Color(0xFFE91E63);

    return Container(
      width: 280,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_outline,
                  size: 18, color: Colors.green.shade600),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Support with a donation',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.coffee_outlined,
                  size: 18, color: Colors.green.shade600),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Buy Me a Coffee or sponsor on GitHub',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.privacy_tip_outlined,
                  size: 18, color: Colors.green.shade600),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('No analytics - everything runs locally',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'Go to Settings \u2192 Support to donate',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
