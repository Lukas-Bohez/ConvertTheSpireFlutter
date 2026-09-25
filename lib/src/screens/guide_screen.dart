import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/build_flags.dart';
import '../utils/l10n.dart';
import 'onboarding_screen.dart';

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
    final isAndroid = !kIsWeb && Platform.isAndroid;

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
                    Icon(
                        kPlayStoreBuild ? Icons.lock_outline : Icons.music_note,
                        size: 48,
                        color: cs.onPrimaryContainer),
                    const SizedBox(height: 12),
                    Text(getAppTitle(),
                        style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer)),
                    const SizedBox(height: 4),
                    Text(getAppSubtitle(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color:
                                cs.onPrimaryContainer.withValues(alpha: 0.8))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
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
                child: Text(context.l10n.showOnboarding),
              ),
            ),
            const SizedBox(height: 16),

            // -- Platform support ----------------------------------─
            _SectionCard(
              icon: Icons.devices,
              title: context.l10n.supportedPlatforms,
              cs: cs,
              child: Column(
                children: [
                  _PlatformRow(
                    icon: Icons.desktop_windows,
                    name: context.l10n.windows,
                    status: context.l10n.fullSupport,
                    detail:
                        context.l10n.downloadsConversionNotificationsFileConv,
                    supported: true,
                  ),
                  const Divider(height: 1),
                  _PlatformRow(
                    icon: Icons.android,
                    name: context.l10n.android,
                    status: context.l10n.fullSupport,
                    detail:
                        context.l10n.downloadsConversionNotificationsSafFolde,
                    supported: true,
                  ),
                  const Divider(height: 1),
                  _PlatformRow(
                    icon: Icons.desktop_mac,
                    name: context.l10n.linux,
                    status: context.l10n.discontinued,
                    detail: context.l10n.officialLinuxBuildsEndedV14,
                    supported: false,
                  ),
                  const Divider(height: 1),
                  _PlatformRow(
                    icon: Icons.apple,
                    name: context.l10n.macosIos,
                    status: context.l10n.untested,
                    detail: context.l10n.mayWorkButNotOfficially,
                    supported: false,
                  ),
                  const Divider(height: 1),
                  _PlatformRow(
                    icon: Icons.web,
                    name: context.l10n.web,
                    status: context.l10n.notSupported,
                    detail: context.l10n.cannotDownloadRunFfmpegBrowser,
                    supported: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // -- Requirements --------------------------------------
            _SectionCard(
              icon: Icons.checklist,
              title: context.l10n.requirements,
              cs: cs,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!kPlayStoreBuild)
                    _RequirementRow(
                      text: context.l10n.ffmpeg,
                      detail:
                          context.l10n.requiredAudioConversionWindowsInstalled,
                    ),
                  if (!kPlayStoreBuild) const SizedBox(height: 8),
                  const SizedBox(height: 8),
                  _RequirementRow(
                    text: context.l10n.internetConnection,
                    detail:
                        context.l10n.neededFetchTorrentMetadataDownload,
                  ),
                  const SizedBox(height: 8),
                  _RequirementRow(
                    text: context.l10n.storageSpace,
                    detail:
                        context.l10n.downloadedFilesSavedChosenDownload,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // -- Quick start --------------------------------------─
            _SectionCard(
              icon: Icons.rocket_launch,
              title: context.l10n.quickStart,
              cs: cs,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StepRow(
                      number: '1',
                      title: context.l10n.setDownloadFolder,
                      detail:
                          context.l10n.goSettingsPickWhereFiles),
                  const SizedBox(height: 12),
                  _StepRow(
                      number: '2',
                      title: context.l10n.browseOpenLinks,
                      detail:
                          context.l10n.useBrowserTabOpenPages),
                  const SizedBox(height: 12),
                  _StepRow(
                      number: '3',
                      title: context.l10n.addQueue,
                      detail:
                          context.l10n.chooseDestinationAddItemsDownload),
                  const SizedBox(height: 12),
                  _StepRow(
                      number: '4',
                      title: context.l10n.actionDownload,
                      detail: kPlayStoreBuild
                          ? context.l10n.goTorrentsTabMonitorProgress
                          : context.l10n.goQueueTabPressDownload),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // -- Tab guide ----------------------------------------─
            _SectionCard(
              icon: Icons.tab,
              title: context.l10n.tabsExplained,
              cs: cs,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: kPlayStoreBuild
                    ? [
                        _FeatureRow(
                            icon: Icons.open_in_browser,
                            name: context.l10n.tabBrowser,
                            detail:
                                context.l10n.browsePagesOpenMagnetTorrent),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.settings,
                            name: context.l10n.tabSettings,
                            detail:
                                context.l10n.configureDownloadFolderAppearanceApp),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.volunteer_activism,
                            name: context.l10n.tabSupport,
                            detail: context.l10n.supportLinksProjectInformation),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.menu_book,
                            name: context.l10n.tabGuide,
                            detail:
                                context.l10n.instructionsSupportedPlatformsTips),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.music_note,
                            name: context.l10n.tabPlayer,
                            detail:
                                context.l10n.builtMediaPlayerLocalFiles),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.swap_vert,
                            name: context.l10n.tabTorrents,
                            detail:
                                context.l10n.torrentManagerDownloadControlCenter),
                      ]
                    : [
                        _FeatureRow(
                            icon: Icons.travel_explore,
                            name: context.l10n.multiSearch,
                            detail:
                                context.l10n.searchAcrossMultipleSourcesOnce),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.open_in_browser,
                            name: context.l10n.tabBrowser,
                            detail:
                                context.l10n.useIntegratedWebViewBrowse),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.queue_music,
                            name: context.l10n.tabQueue,
                            detail:
                                context.l10n.viewManageDownloadsStartAll),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.playlist_play,
                            name: context.l10n.tabPlaylists,
                            detail:
                                context.l10n.loadCollectionCompareAgainstLocal),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.upload_file,
                            name: context.l10n.bulkImport,
                            detail:
                                context.l10n.pasteListLinksImportFrom),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.bar_chart,
                            name: context.l10n.stats,
                            detail:
                                context.l10n.viewDownloadStatisticsTotalsSuccess),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.settings,
                            name: context.l10n.tabSettings,
                            detail:
                                context.l10n.configureDownloadFoldersParallelWorkers),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.transform,
                            name: context.l10n.tabConvert,
                            detail:
                                context.l10n.convertAnyLocalAudioVideo),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.list_alt,
                            name: context.l10n.tabLogs,
                            detail:
                                context.l10n.viewDetailedApplicationLogsDebugging),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.menu_book,
                            name: context.l10n.tabGuide,
                            detail:
                                context.l10n.screenInstructionsSupportedPlatformsTips),
                        const SizedBox(height: 8),
                        _FeatureRow(
                            icon: Icons.music_note,
                            name: context.l10n.tabPlayer,
                            detail:
                                context.l10n.builtMediaPlayerLocalFiles2),
                      ],
              ),
            ),
            const SizedBox(height: 12),

            // -- Torrents: this used to be a guide of its own inside
            // the Torrents section.
            _SectionCard(
              icon: Icons.swap_vert,
              title: context.l10n.tabTorrents,
              cs: cs,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TipRow(
                    title: context.l10n.gettingStarted,
                    detail: isAndroid
                        ? context.l10n.tapButtonPasteMagnetLink
                        : context.l10n.dragTorrentFileOntoWindow,
                  ),
                  const SizedBox(height: 10),
                  _TipRow(
                    title: context.l10n.understandingDownloadProgress,
                    detail: context.l10n.downloadingPiecesBeingReceivedFrom,
                  ),
                  const SizedBox(height: 10),
                  _TipRow(
                    title: context.l10n.verifyingRedownloading,
                    detail: context.l10n.ifDownloadedFileSeemsCorrupt,
                  ),
                  const SizedBox(height: 10),
                  _TipRow(
                    title: isAndroid
                        ? context.l10n.androidTips
                        : context.l10n.desktopTips,
                    detail: isAndroid
                        ? context.l10n
                            .disableBatteryOptimisationVaultSpire(getAppTitle())
                        : context.l10n.appKeepsDownloadingWhenMinimised,
                  ),
                  const SizedBox(height: 10),
                  _TipRow(
                    title: context.l10n.privacyData,
                    detail:
                        context.l10n.vaultSpireStoresAllData(getAppTitle()),
                  ),
                  const SizedBox(height: 10),
                  _TipRow(
                    title: context.l10n.legalUseOnly,
                    detail: context.l10n
                        .vaultSpireDesignedExclusivelyLegal(getAppTitle()),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isAndroid
                        ? context.l10n.proTipSeedRatioMatters
                        : context.l10n.proTipBittorrentProtocolPeer,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (!kPlayStoreBuild) ...[
              // -- Tips ----------------------------------------------
              _SectionCard(
                icon: Icons.lightbulb_outline,
                title: context.l10n.tipsTroubleshooting,
                cs: cs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TipRow(
                      title: context.l10n.downloadsFail0,
                      detail:
                          context.l10n.usuallyMeansFfmpegMissingWindows,
                    ),
                    const SizedBox(height: 10),
                    _TipRow(
                      title: context.l10n.sourceSitesBlockRequests,
                      detail:
                          context.l10n.someSourceSitesMayTemporarily,
                    ),
                    const SizedBox(height: 10),
                    _TipRow(
                        title: context.l10n.largeLibrariesSlow,
                        detail:
                            context.l10n.whenLoadingLargeCollectionsUse),
                    const SizedBox(height: 10),
                    _TipRow(
                      title: context.l10n.androidChooseWritableFolder,
                      detail:
                          context.l10n.androidMustPickDownloadFolder,
                    ),
                    const SizedBox(height: 10),
                    _TipRow(
                      title: context.l10n.parallelWorkers,
                      detail:
                          context.l10n.moreWorkersMeansFasterBatch,
                    ),
                    const SizedBox(height: 10),
                    _TipRow(
                      title: context.l10n.needRefresher,
                      detail:
                          context.l10n.tapShowOnboardingTopScreen,
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
                title: context.l10n.supportedFormats,
                cs: cs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FormatRow(
                        format: 'MP3',
                        detail:
                            context.l10n.universalAudioFormatBestCompatibility),
                    const SizedBox(height: 6),
                    _FormatRow(
                        format: 'M4A',
                        detail:
                            context.l10n.aacAudioMp4ContainerBetter),
                    const SizedBox(height: 6),
                    _FormatRow(
                        format: 'MP4',
                        detail:
                            context.l10n.videoAudioKeepsVideoTrack),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // -- Current platform info ----------------------------─
            _SectionCard(
              icon: Icons.info_outline,
              title: context.l10n.environment,
              cs: cs,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: context.l10n.platform, value: _platformName(context)),
                  const SizedBox(height: 4),
                  _InfoRow(
                      label: context.l10n.dartVersion,
                      value:
                          kIsWeb ? 'N/A' : Platform.version.split(' ').first),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static String _platformName(BuildContext context) {
    if (kIsWeb) return context.l10n.web;
    if (Platform.isWindows) return context.l10n.windows;
    if (Platform.isAndroid) return context.l10n.android;
    if (Platform.isLinux) return context.l10n.linux;
    if (Platform.isMacOS) return context.l10n.macos;
    if (Platform.isIOS) return context.l10n.ios;
    return context.l10n.unknown;
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
