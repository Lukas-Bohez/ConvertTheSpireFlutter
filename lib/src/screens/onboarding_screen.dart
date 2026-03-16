import 'package:flutter/material.dart';

/// A multi-page onboarding flow that introduces the app's features.
///
/// Used in two places:
///  * Automatically on first launch – the caller marks "seenOnboarding" when
///    [onFinish] fires.
///  * Manually from the Guide screen via a button.
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
  int _page = 0;

  // ─── Pages ───────────────────────────────────────────────────────────────

  static const _pages = <_OnboardingPage>[
    // Welcome
    _OnboardingPage(
      icon: Icons.download_rounded,
      title: 'Welcome',
      detail: 'Convert the Spire Reborn is a cross-platform media toolkit. '
          'Download audio & video from dozens of sites, convert formats, '
          'cast to your TV, and more \u2014 all from one app.',
      color: Color(0xFF00897B),
      preview: _WelcomePreview(),
    ),

    // Supported Platforms
    _OnboardingPage(
      icon: Icons.language_rounded,
      title: 'Supported Platforms',
      detail: 'Not just YouTube! This app uses yt-dlp under the hood, '
          'supporting 1\u202F000+ websites. Here are some popular ones:',
      color: Color(0xFFFF6D00),
      preview: _PlatformsPreview(),
    ),

    // Search
    _OnboardingPage(
      icon: Icons.search_rounded,
      title: 'Search',
      detail: 'Look up a video by keyword or paste a link from any supported '
          'site. Preview the result and pick a format before downloading.',
      color: Color(0xFF6C63FF),
      preview: _SearchPreview(),
    ),

    // Multi-Search
    _OnboardingPage(
      icon: Icons.travel_explore_rounded,
      title: 'Multi-Search',
      detail: 'Fetch results from YouTube and SoundCloud simultaneously. '
          'Tap a row to hear a preview.',
      color: Color(0xFF43CFBB),
    ),

    // Browser
    _OnboardingPage(
      icon: Icons.open_in_browser_rounded,
      title: 'Browser',
      detail: 'Browse the web in the built-in view and add videos directly '
          'to the queue without leaving the app.',
      color: Color(0xFF4A90D9),
    ),

    // Queue
    _OnboardingPage(
      icon: Icons.queue_music_rounded,
      title: 'Queue',
      detail: 'Manage your downloads. Start all, cancel, retry failures, '
          'cast to your TV, or show completed files in your file manager.',
      color: Color(0xFFE07B54),
      preview: _QueuePreview(),
    ),

    // Playlists
    _OnboardingPage(
      icon: Icons.playlist_play_rounded,
      title: 'Playlists',
      detail: 'Load a playlist, compare against a local folder to spot '
          'missing tracks, and batch-download.',
      color: Color(0xFFAB6BD9),
    ),

    // Bulk Import
    _OnboardingPage(
      icon: Icons.upload_file_rounded,
      title: 'Bulk Import',
      detail: 'Paste a list of names or import a text/CSV file to enqueue '
          'many items at once.',
      color: Color(0xFF5BA85A),
    ),

    // Stats
    _OnboardingPage(
      icon: Icons.bar_chart_rounded,
      title: 'Stats',
      detail: 'See download totals, success rate, format breakdown, top '
          'artists, and trends over time.',
      color: Color(0xFFD4A017),
    ),

    // Settings
    _OnboardingPage(
      icon: Icons.settings_rounded,
      title: 'Settings',
      detail: 'Choose download folder, quality defaults (1080p video, '
          '320\u202Fkbps audio), FFmpeg options, retry behaviour, and '
          'appearance.',
      color: Color(0xFF607D8B),
    ),

    // Convert
    _OnboardingPage(
      icon: Icons.transform_rounded,
      title: 'Convert',
      detail: 'Convert any local audio/video file between popular formats '
          'using FFmpeg.',
      color: Color(0xFFE57373),
    ),

    // Logs
    _OnboardingPage(
      icon: Icons.list_alt_rounded,
      title: 'Logs',
      detail:
          'Inspect the internal application log. Copy or clear at any time.',
      color: Color(0xFF78909C),
    ),

    // Guide
    _OnboardingPage(
      icon: Icons.menu_book_rounded,
      title: 'Guide',
      detail: 'A help screen you can revisit from the Guide tab.',
      color: Color(0xFF26A69A),
    ),

    // Player
    _OnboardingPage(
      icon: Icons.music_note_rounded,
      title: 'Player',
      detail: 'Built-in media player for your files. Playback, shuffle, '
          'repeat, and a simple library.',
      color: Color(0xFF7E57C2),
    ),

    // Support CTA (last page)
    _OnboardingPage(
      icon: Icons.toll_rounded,
      title: 'Support Us',
      detail: 'You can help the project by mining QUBIC tokens with idle '
          'CPU cycles. It\u2019s 100\u202F% opt-in, battery-aware, '
          'and runs in sandboxed isolates.\n\n'
          'Enable it now or later from Settings. Every bit helps!',
      color: Color(0xFFE91E63),
      preview: _SupportPreview(),
    ),
  ];

  // ─── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
    _controller = PageController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _setupAnimations();

    // Delay the initial animation until after the first frame is rendered to
    // avoid blocking the UI thread during initial layout on slower devices.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animController.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Precache any images used in the onboarding flow so that swiping between
    // pages doesn't cause a decode/paint jank (black flash) on first display.
    // If you add image assets to onboarding pages, add them here with
    // `precacheImage(AssetImage(...), context);`.
  }

  void _setupAnimations() {
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
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
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _back() {
    if (_page > 0) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
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

  // ─── Sub-builders ───────────────────────────────────────────────────────

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
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
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
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
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
          duration: const Duration(milliseconds: 250),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          duration: const Duration(milliseconds: 200),
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

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final squareSide = (screenWidth * 0.50).clamp(150.0, 280.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Convert the Spire',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildThemeToggle(theme),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
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
                          horizontal: 28.0, vertical: 12),
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
                                // Icon card with coloured glow
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
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(
                                      color: p.color.withValues(alpha: 0.30),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: p.color.withValues(alpha: 0.15),
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

                                // Optional preview
                                if (p.preview != null) ...[
                                  const SizedBox(height: 20),
                                  p.preview!,
                                ],

                                const SizedBox(height: 28),

                                Text(
                                  p.title,
                                  style:
                                      theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: p.color,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  p.detail,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge?.copyWith(
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8),
              child: _buildControls(theme),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ─── Data model ─────────────────────────────────────────────────────────────

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

/// Keeps a page alive once it has been built, preventing transient black
/// flashes when the user rapidly swipes between pages.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child, Key? key}) : super(key: key);

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

// ─── Preview widgets ────────────────────────────────────────────────────────

/// Welcome page — shows a brief feature overview.
class _WelcomePreview extends StatelessWidget {
  const _WelcomePreview();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDDDDD);

    const features = [
      (Icons.download_rounded, 'Multi-site downloads'),
      (Icons.transform_rounded, 'Format conversion'),
      (Icons.cast_rounded, 'DLNA / Cast to TV'),
      (Icons.toll_rounded, 'QUBIC mining support'),
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
                      Text(f.$2,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

/// Supported platforms grid.
class _PlatformsPreview extends StatelessWidget {
  const _PlatformsPreview();

  static const _platforms = [
    'YouTube',
    'SoundCloud',
    'Vimeo',
    'Dailymotion',
    'Twitch',
    'Bandcamp',
    'Reddit',
    'Twitter / X',
    'Facebook',
    'Instagram',
    'TikTok',
    'Bilibili',
    'Rumble',
    'Mixcloud',
    'Odysee',
    '1000+ more',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = const Color(0xFFFF6D00);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: _platforms.map((name) {
        final isMore = name.startsWith('1000');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isMore
                ? accent.withValues(alpha: 0.15)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.withValues(alpha: 0.10)),
            borderRadius: BorderRadius.circular(16),
            border: isMore
                ? Border.all(color: accent.withValues(alpha: 0.4))
                : null,
          ),
          child: Text(
            name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isMore ? FontWeight.bold : FontWeight.w500,
              color: isMore ? accent : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Search tab preview.
class _SearchPreview extends StatelessWidget {
  const _SearchPreview();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDDDDD);

    return Container(
      key: const Key('onboarding_preview_search'),
      width: 260,
      padding: const EdgeInsets.all(10),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            enabled: false,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              hintText: 'Search or paste a link\u2026',
              hintStyle: TextStyle(
                  fontSize: 13, color: Colors.grey.withValues(alpha: 0.7)),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: border),
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.grey.withValues(alpha: 0.06),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.music_video_rounded,
                  size: 20, color: Color(0xFF6C63FF)),
            ),
            title: const Text('Example video title',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('3:42 \u00b7 MP3 320 kbps',
                style: TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.add_circle_outline_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Queue tab preview.
class _QueuePreview extends StatelessWidget {
  const _QueuePreview();

  static const _items = [
    (
      label: 'Live at the Spire',
      icon: Icons.pause_circle_filled_rounded,
      color: Color(0xFF607D8B),
      status: 'Paused',
    ),
    (
      label: 'Tutorial Walkthrough',
      icon: Icons.download_rounded,
      color: Color(0xFF43CFBB),
      status: 'Downloading\u2026',
    ),
    (
      label: 'Broken link example',
      icon: Icons.error_outline_rounded,
      color: Color(0xFFE57373),
      status: 'Failed',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDDDDD);

    return Container(
      key: const Key('onboarding_preview_queue'),
      width: 260,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        children: _items
            .map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(item.icon, size: 20, color: item.color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.label,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis),
                            Text(item.status,
                                style:
                                    TextStyle(fontSize: 11, color: item.color)),
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
              Icon(Icons.shield_outlined,
                  size: 18, color: Colors.green.shade600),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Mines QUBIC tokens for the developer',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.battery_charging_full,
                  size: 18, color: Colors.green.shade600),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Auto-pauses below 30% battery',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.pause_circle_outline,
                  size: 18, color: Colors.green.shade600),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('One tap to stop, instantly',
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
                'Enable in Settings \u2192 Support the Project',
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
