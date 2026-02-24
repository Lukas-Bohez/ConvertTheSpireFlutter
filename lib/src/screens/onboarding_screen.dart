import 'package:flutter/material.dart';

/// A simple multi-page onboarding flow that explains each of the main tabs.
///
/// The widget is used in two places:
///  * Automatically when the app is launched for the first time (after
///    installation) – the caller should mark the "seenOnboarding" flag when
///    [onFinish] is invoked.
///  * Manually from the guide screen via a button. In that case the caller can
///    just pop the route when the user finishes the tour.
class OnboardingScreen extends StatefulWidget {
  /// Called when the user completes or skips the tour.
  final VoidCallback onFinish;

  /// Called when the user toggles the theme inside onboarding.
  /// The host app should rebuild with the new [ThemeMode].
  final ValueChanged<ThemeMode>? onThemeChanged;

  /// The current theme mode, so the toggle reflects the real state.
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

  static const _pages = <_OnboardingPage>[
    _OnboardingPage(
      icon: Icons.search_rounded,
      title: 'Search',
      detail:
          'Look up a YouTube video by keyword or paste a link. Preview the result and pick a format before adding to the queue.',
      color: Color(0xFF6C63FF),
      preview: _SearchPreview(),
    ),
    _OnboardingPage(
      icon: Icons.travel_explore_rounded,
      title: 'Multi‑Search',
      detail:
          'Fetch results from multiple sources simultaneously. Tap a row to hear a preview.',
      color: Color(0xFF43CFBB),
    ),
    _OnboardingPage(
      icon: Icons.open_in_browser_rounded,
      title: 'Browser',
      detail:
          'Browse the web in the built‑in view and add videos directly to the queue without leaving the app.',
      color: Color(0xFF4A90D9),
    ),
    _OnboardingPage(
      icon: Icons.queue_music_rounded,
      title: 'Queue',
      detail:
          'Manage your pending downloads. Start all, cancel items, retry failures, or remove tracks you no longer need.',
      color: Color(0xFFE07B54),
      preview: _QueuePreview(),
    ),
    _OnboardingPage(
      icon: Icons.playlist_play_rounded,
      title: 'Playlists',
      detail:
          'Load a YouTube playlist, compare it against a local folder to spot missing tracks, and batch‑download.',
      color: Color(0xFFAB6BD9),
    ),
    _OnboardingPage(
      icon: Icons.upload_file_rounded,
      title: 'Bulk Import',
      detail:
          'Paste a list of names or import a text/CSV file to enqueue many items at once.',
      color: Color(0xFF5BA85A),
    ),
    _OnboardingPage(
      icon: Icons.bar_chart_rounded,
      title: 'Stats',
      detail:
          'See download totals, success rate, format breakdown, top artists, and trends over time.',
      color: Color(0xFFD4A017),
    ),
    _OnboardingPage(
      icon: Icons.settings_rounded,
      title: 'Settings',
      detail:
          'Choose download folder, workers, FFmpeg options, retry behavior, and notification preferences.',
      color: Color(0xFF607D8B),
    ),
    _OnboardingPage(
      icon: Icons.transform_rounded,
      title: 'Convert',
      detail:
          'Convert any local audio/video file between popular formats using FFmpeg.',
      color: Color(0xFFE57373),
    ),
    _OnboardingPage(
      icon: Icons.list_alt_rounded,
      title: 'Logs',
      detail:
          'Inspect the internal application log. Copy it or clear it if needed.',
      color: Color(0xFF78909C),
    ),
    _OnboardingPage(
      icon: Icons.menu_book_rounded,
      title: 'Guide',
      detail:
          'This help screen you are currently looking at. Revisit it any time from the Guide tab.',
      color: Color(0xFF26A69A),
    ),
    _OnboardingPage(
      icon: Icons.music_note_rounded,
      title: 'Player',
      detail:
          'Built‑in media player for your own files. Control playback, shuffle, repeat, and manage a simple library.',
      color: Color(0xFF7E57C2),
    ),
  ];

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
    _animController.forward();
  }

  void _setupAnimations() {
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOut));
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
      ThemeMode.light  => ThemeMode.dark,
      ThemeMode.dark   => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    setState(() => _themeMode = next);
    widget.onThemeChanged?.call(next);
  }

  IconData get _themeIcon => switch (_themeMode) {
        ThemeMode.light  => Icons.light_mode_rounded,
        ThemeMode.dark   => Icons.dark_mode_rounded,
        ThemeMode.system => Icons.brightness_auto_rounded,
      };

  String get _themeLabel => switch (_themeMode) {
        ThemeMode.light  => 'Light',
        ThemeMode.dark   => 'Dark',
        ThemeMode.system => 'Auto',
      };

  // ─── Sub-builders ──────────────────────────────────────────────────────────

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
      message: 'Theme: $_themeLabel — tap to cycle',
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
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isFirst
              ? TextButton(
                  key: const ValueKey('skip'),
                  onPressed: widget.onFinish,
                  style: TextButton.styleFrom(
                    foregroundColor: onSurface.withValues(alpha: 0.70),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  child: const Text(
                    'Skip tour',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                )
              : TextButton.icon(
                  key: const ValueKey('back'),
                  onPressed: _back,
                  style: TextButton.styleFrom(
                    foregroundColor: onSurface.withValues(alpha: 0.65),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 15),
                  label: const Text(
                    'Back',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
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

  // ─── Build ─────────────────────────────────────────────────────────────────

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
              child: PageView.builder(
                controller: _controller,
                onPageChanged: _onPageChanged,
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final p = _pages[index];
                  return Padding(
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

                              // Optional live preview
                              if (p.preview != null) ...[
                                const SizedBox(height: 20),
                                p.preview!,
                              ],

                              const SizedBox(height: 28),

                              Text(
                                p.title,
                                style: theme.textTheme.headlineMedium?.copyWith(
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
                  );
                },
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

// ─── Data model ──────────────────────────────────────────────────────────────

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  /// Optional widget shown below the icon card as a visual preview.
  final Widget? preview;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
    this.preview,
  });
}

// ─── Preview widgets ─────────────────────────────────────────────────────────

/// Static mock of the Search tab UI.
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
              hintText: 'Search or paste a link…',
              hintStyle: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.withValues(alpha: 0.7)),
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
            subtitle: const Text('3:42 · MP3 320 kbps',
                style: TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.add_circle_outline_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Static mock of the Queue tab showing a few download rows.
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
      status: 'Downloading…',
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
        children: _items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(item.icon, size: 20, color: item.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.status,
                        style: TextStyle(fontSize: 11, color: item.color),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}