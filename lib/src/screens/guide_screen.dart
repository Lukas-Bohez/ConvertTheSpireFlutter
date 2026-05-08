import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'onboarding_screen.dart';
import '../config/build_flags.dart';
import '../widgets/dpad_focusable_surface.dart';

/// In-app guide covering usage instructions, supported platforms,
/// and feature explanations.
class GuideScreen extends StatelessWidget {
  /// Current theme mode so the onboarder toggle starts in the right state.
  final ThemeMode themeMode;

  /// Called if the user cycles the theme while running through onboarding.
  /// GuideScreen doesn't itself manage theme, it simply proxies to the host.
  final ValueChanged<ThemeMode>? onThemeChanged;

  const GuideScreen({
    super.key,
    this.themeMode = ThemeMode.system,
    this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: true,
      child: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // -- Header --------------------------------------------─
            Card(
              color: cs.primaryContainer,
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(kPlayStoreBuild ? Icons.lock_outline : Icons.music_note,
                        size: 48, color: cs.onPrimaryContainer),
                    const SizedBox(height: 12),
                    Text(getAppTitle(),
                        style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer)),
                    const SizedBox(height: 4),
                      Text(getAppSubtitle(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: DpadFocusableSurface(
                autofocus: true,
                onSelect: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => OnboardingScreen(
                            onFinish: () {
                              Navigator.of(context).pop();
                            },
                            themeMode: themeMode,
                            onThemeChanged: onThemeChanged,
                          )));
                },
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => OnboardingScreen(
                              onFinish: () {
                                Navigator.of(context).pop();
                              },
                              themeMode: themeMode,
                              onThemeChanged: onThemeChanged,
                            )));
                  },
                  child: const Text('Show onboarding'),
                ),
              ),
            ),
            const SizedBox(height: 16),

          // -- Platform support ----------------------------------─
          _SectionCard(
            icon: Icons.devices,
            title: 'Supported Platforms',
            cs: cs,
            child: Column(
              children: [
                _PlatformRow(
                  icon: Icons.desktop_windows,
                  name: 'Windows',
                  status: 'Full support',
                  detail:
                      'Downloads, conversion, notifications, file converter',
                  supported: true,
                ),
                const Divider(height: 1),
                _PlatformRow(
                  icon: Icons.android,
                  name: 'Android',
                  status: 'Full support',
                  detail:
                      'Downloads, conversion, notifications, SAF folder picker',
                  supported: true,
                ),
                const Divider(height: 1),
                _PlatformRow(
                  icon: Icons.desktop_mac,
                  name: 'Linux',
                  status: 'Full support',
                  detail:
                      'Downloads, conversion, notifications. Video playback requires the system libmpv runtime (install mpv/libmpv via your package manager).',
                  supported: true,
                ),
                const Divider(height: 1),
                _PlatformRow(
                  icon: Icons.apple,
                  name: 'macOS / iOS',
                  status: 'Untested',
                  detail: 'May work but not officially supported',
                  supported: false,
                ),
                const Divider(height: 1),
                _PlatformRow(
                  icon: Icons.web,
                  name: 'Web',
                  status: 'Not supported',
                  detail: 'Cannot download or run FFmpeg in a browser',
                  supported: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // -- Requirements --------------------------------------
          _SectionCard(
            icon: Icons.checklist,
            title: 'Requirements',
            cs: cs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!kPlayStoreBuild)
                  const _RequirementRow(
                    text: 'FFmpeg',
                    detail:
                        'Required for audio conversion. On Windows it is installed automatically on first launch. On Linux, install via your package manager (e.g. sudo apt install ffmpeg).',
                  ),
                if (!kPlayStoreBuild) const SizedBox(height: 8),
                SizedBox(height: 8),
                const _RequirementRow(
                  text: 'Internet connection',
                  detail: 'Needed to fetch torrent metadata and download sources.',
                ),
                SizedBox(height: 8),
                const _RequirementRow(
                  text: 'Storage space',
                  detail:
                      'Downloaded files are saved to your chosen download folder. Videos can be large before conversion.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // -- Quick start --------------------------------------─
          _SectionCard(
            icon: Icons.rocket_launch,
            title: 'Quick Start',
            cs: cs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _StepRow(
                    number: '1',
                    title: 'Set download folder',
                    detail:
                        'Go to Settings and pick where files should be saved.'),
                const SizedBox(height: 12),
                const _StepRow(
                    number: '2',
                    title: 'Browse & open links',
                    detail:
                        'Use the Browser tab to open pages, magnet links, and .torrent links safely inside the app.'),
                const SizedBox(height: 12),
                const _StepRow(
                    number: '3',
                    title: 'Add to queue',
                    detail:
                        'Choose your destination and add items to the download queue.'),
                const SizedBox(height: 12),
                _StepRow(
                    number: '4',
                    title: 'Download',
                    detail: kPlayStoreBuild
                        ? 'Go to the Torrents tab to monitor progress, pause/resume, and manage completed files.'
                        : 'Go to the Queue tab and press "Download All". The app fetches the selected content and processes it with FFmpeg when needed.'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // -- Tab guide ----------------------------------------─
          _SectionCard(
            icon: Icons.tab,
            title: 'Tabs Explained',
            cs: cs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: kPlayStoreBuild
                ? const [
                  _FeatureRow(
                    icon: Icons.open_in_browser,
                    name: 'Browser',
                    detail:
                      'Browse pages and open magnet or torrent links in-app.'),
                  SizedBox(height: 8),
                  _FeatureRow(
                    icon: Icons.settings,
                    name: 'Settings',
                    detail:
                      'Configure download folder, appearance, and app behavior.'),
                  SizedBox(height: 8),
                  _FeatureRow(
                    icon: Icons.volunteer_activism,
                    name: 'Support',
                    detail: 'Support links and project information.'),
                  SizedBox(height: 8),
                  _FeatureRow(
                    icon: Icons.menu_book,
                    name: 'Guide',
                    detail:
                      'Instructions, supported platforms, and tips.'),
                  SizedBox(height: 8),
                  _FeatureRow(
                    icon: Icons.music_note,
                    name: 'Player',
                    detail:
                      'Built-in media player for local files with shuffle and repeat.'),
                  SizedBox(height: 8),
                  _FeatureRow(
                    icon: Icons.download,
                    name: 'Vault',
                    detail:
                      'Torrent manager and download control center.'),
                ]
                : const [
              _FeatureRow(
                    icon: Icons.search,
                    name: 'Search',
                  detail:
                    'Search by keyword or paste a magnet / torrent link. Preview results and add them to the queue.'),
                SizedBox(height: 8),
                _FeatureRow(
                    icon: Icons.travel_explore,
                    name: 'Multi-Search',
                  detail:
                    'Search across multiple sources at once and compare results side by side.'),
                SizedBox(height: 8),
                _FeatureRow(
                    icon: Icons.open_in_browser,
                    name: 'Browser',
                  detail:
                    'Use an integrated web view to browse supported sites and open magnet or torrent links directly.'),
                SizedBox(height: 8),
                _FeatureRow(
                    icon: Icons.queue_music,
                    name: 'Queue',
                    detail:
                        'View and manage downloads. Start all, cancel, retry failed, or remove items.'),
                SizedBox(height: 8),
                _FeatureRow(
                    icon: Icons.playlist_play,
                    name: 'Playlists',
                  detail:
                    'Load a collection, compare against a local folder to find missing items, and batch-download them.'),
                SizedBox(height: 8),
                _FeatureRow(
                    icon: Icons.upload_file,
                    name: 'Bulk Import',
                  detail:
                    'Paste a list of links or import from a text/CSV file to add many items to the queue at once.'),
                SizedBox(height: 8),
                _FeatureRow(
                  icon: Icons.bar_chart,
                  name: 'Stats',
                  detail:
                    'View download statistics: totals, success rate, format breakdown, top artists, and trends over time.'),
                SizedBox(height: 8),
                _FeatureRow(
                    icon: Icons.settings,
                    name: 'Settings',
                  detail:
                    'Configure download folders, parallel workers, FFmpeg, retry behavior, and notifications.'),
                SizedBox(height: 8),
                _FeatureRow(
                    icon: Icons.transform,
                    name: 'Convert',
                  detail:
                    'Convert any local audio/video file between formats using FFmpeg.'),
                SizedBox(height: 8),
                _FeatureRow(
                    icon: Icons.list_alt,
                    name: 'Logs',
                    detail:
                        'View detailed application logs for debugging. Copy or clear the log history.'),
                SizedBox(height: 8),
                _FeatureRow(
                    icon: Icons.menu_book,
                    name: 'Guide',
                    detail:
                        'This screen! Instructions, supported platforms, and tips.'),
                SizedBox(height: 8),
                _FeatureRow(
                    icon: Icons.music_note,
                    name: 'Player',
                    detail:
                        'Built‑in media player for your local files; control playback, shuffle, repeat and manage a library.'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (!kPlayStoreBuild) ...[
            // -- Tips ----------------------------------------------
            _SectionCard(
              icon: Icons.lightbulb_outline,
              title: 'Tips & Troubleshooting',
              cs: cs,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _TipRow(
                    title: 'Downloads fail at 0%',
                    detail:
                        'This usually means FFmpeg is missing. On Windows the app installs it automatically; on Linux run: sudo apt install ffmpeg (or dnf install ffmpeg on Fedora).',
                  ),
                  SizedBox(height: 10),
                  _TipRow(
                    title: 'Source sites block requests',
                    detail:
                        'Some source sites may temporarily block rapid requests. The app will automatically retry with backoff. You can increase retry count in Settings.',
                  ),
                  SizedBox(height: 10),
                  _TipRow(
                    title: 'Large libraries are slow',
                    detail:
                        'When loading large collections, use the preview limit to load just 10-50 items first. You can always load more.'),
                  SizedBox(height: 10),
                  _TipRow(
                    title: 'Android: choose a writable folder',
                    detail:
                        'On Android you must pick a download folder through the system file picker so the app gets write permission.',
                  ),
                  SizedBox(height: 10),
                  _TipRow(
                    title: 'Linux: enable video playback',
                    detail:
                        'Install mpv/libmpv with your package manager (e.g. sudo apt install mpv libmpv-dev) to enable video playback. Without libmpv the app will fall back to audio-only mode.',
                  ),
                  SizedBox(height: 10),
                  _TipRow(
                    title: 'Parallel workers',
                    detail:
                        'More workers means faster batch downloads but uses more bandwidth and may trigger rate limits. 2-3 is recommended.',
                  ),
                  SizedBox(height: 10),
                  _TipRow(
                    title: 'Need a refresher?',
                    detail:
                        'Tap "Show onboarding" at the top of this screen to walk through every tab again.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // -- Supported formats --------------------------------─
          if (!kPlayStoreBuild) ...[
            _SectionCard(
              icon: Icons.audio_file,
              title: 'Supported Formats',
              cs: cs,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _FormatRow(
                      format: 'MP3',
                      detail:
                          'Universal audio format. Best compatibility across all devices and players.'),
                  SizedBox(height: 6),
                  _FormatRow(
                      format: 'M4A',
                      detail:
                          'AAC audio in MP4 container. Better quality than MP3 at same bitrate. Works on Apple devices and modern players.'),
                  SizedBox(height: 6),
                  _FormatRow(
                      format: 'MP4',
                      detail:
                      'Video with audio. Keeps the video track intact when that is the selected target format.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // -- Current platform info ----------------------------─
          _SectionCard(
            icon: Icons.info_outline,
            title: 'Your Environment',
            cs: cs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Platform', value: _platformName()),
                const SizedBox(height: 4),
                _InfoRow(
                    label: 'Dart version',
                    value: kIsWeb ? 'N/A' : Platform.version.split(' ').first),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
    );
  }

  static String _platformName() {
    if (kIsWeb) return 'Web';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isIOS) return 'iOS';
    return 'Unknown';
  }
}

// --─ Reusable section card --------------------------------------------------─

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final ColorScheme cs;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.cs,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const Divider(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

// --─ Platform row ------------------------------------------------------------

class _PlatformRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String status;
  final String detail;
  final bool supported;

  const _PlatformRow({
    required this.icon,
    required this.name,
    required this.status,
    required this.detail,
    required this.supported,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 28, color: supported ? Colors.green : Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: supported
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(status,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: supported
                                  ? Colors.green.shade700
                                  : Colors.grey.shade600)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(detail,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --─ Requirement row --------------------------------------------------------─

class _RequirementRow extends StatelessWidget {
  final String text;
  final String detail;

  const _RequirementRow({required this.text, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, size: 18, color: Colors.green),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                TextSpan(
                    text: '$text  ',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: detail),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --─ Step row ----------------------------------------------------------------

class _StepRow extends StatelessWidget {
  final String number;
  final String title;
  final String detail;

  const _StepRow(
      {required this.number, required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: cs.primary,
          child: Text(number,
              style: TextStyle(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(detail,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

// --─ Feature row ------------------------------------------------------------─

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String detail;

  const _FeatureRow(
      {required this.icon, required this.name, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                TextSpan(
                    text: '$name  ',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: detail),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --─ Tip row ----------------------------------------------------------------─

class _TipRow extends StatelessWidget {
  final String title;
  final String detail;

  const _TipRow({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.tips_and_updates, size: 18, color: Colors.amber.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                TextSpan(
                    text: '$title\n',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: detail),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --─ Format row --------------------------------------------------------------

class _FormatRow extends StatelessWidget {
  final String format;
  final String detail;

  const _FormatRow({required this.format, required this.detail});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          padding: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(format,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: cs.onPrimaryContainer)),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(detail,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
      ],
    );
  }
}

// --─ Info row ----------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
