import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/build_flags.dart';
import '../features/colour_rewards/watch_ad_card.dart';
import '../services/ad_service.dart';
import '../services/purchase_service.dart';
import '../state/app_controller.dart';
import '../utils/l10n.dart';
import '../utils/snack.dart';
import '../widgets/monetization_widgets.dart';

/// Support and monetization page for donations, ads, and the Remove Ads unlock.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  bool _lastAdFree = PurchaseService.instance.isAdFree;
  bool _isRunningAdAction = false;
  int _adsWatchedCount = 0;
  Timer? _adBreakRefreshTimer;

  @override
  void initState() {
    super.initState();
    PurchaseService.instance.addListener(_handlePurchaseChanged);
    _adsWatchedCount = AdService.instance.adsWatchedCount;
    _adBreakRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      if (AdService.instance.hasTemporaryAdBreak) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    PurchaseService.instance.removeListener(_handlePurchaseChanged);
    _adBreakRefreshTimer?.cancel();
    super.dispose();
  }

  void _handlePurchaseChanged() {
    final purchaseService = PurchaseService.instance;
    if (!mounted) return;
    if (purchaseService.isAdFree && !_lastAdFree) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.removeAdsUnlockedAllAds)),
      );
    }
    _lastAdFree = purchaseService.isAdFree;
    setState(() {});
  }

  String _formatDuration(Duration duration) {
    final totalMinutes = duration.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '$minutes min';
    return '${hours}u ${minutes}m';
  }

  Future<void> _openUrl(String url) async {
    AdService.instance.registerInteraction();
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        Snack.show(context, context.l10n.couldNotLaunch(url), level: SnackLevel.error);
      }
    }
  }

  Future<void> _buyRemoveAds() async {
    AdService.instance.registerInteraction();
    final purchase = PurchaseService.instance;
    if (!purchase.storeAvailable) {
      Snack.show(
        context,
        context.l10n.removeAdsPurchasesOnlyAvailable,
        level: SnackLevel.error,
      );
      return;
    }

    await purchase.purchaseRemoveAds();
    if (mounted) {
      Snack.show(
        context,
        context.l10n.openingPlayPurchaseFlow,
        level: SnackLevel.info,
      );
    }
  }

  Future<void> _restorePurchases() async {
    AdService.instance.registerInteraction();
    await PurchaseService.instance.restorePurchases();
    if (mounted) {
      Snack.show(context, context.l10n.restoreRequestSent, level: SnackLevel.info);
    }
  }

  ThemeMode _resolveThemeMode(String? mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeLabel(String? mode) {
    switch (mode) {
      case 'light':
        return context.l10n.light;
      case 'dark':
        return context.l10n.dark;
      default:
        return context.l10n.system;
    }
  }

  Widget _buildAppearanceCard(ThemeData theme, AppController controller) {
    final settings = controller.settings;
    final currentMode = settings?.themeMode ?? 'system';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.palette_outlined),
                const SizedBox(width: 8),
                Text(
                  context.l10n.appearance,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.chooseAppThemeUsedAcross,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'system',
                  label: Text(context.l10n.system),
                  icon: const Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: 'light',
                  label: Text(context.l10n.light),
                  icon: const Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: 'dark',
                  label: Text(context.l10n.dark),
                  icon: const Icon(Icons.dark_mode),
                ),
              ],
              selected: {currentMode},
              onSelectionChanged: (value) async {
                final nextMode = value.first;
                await controller.setThemeMode(_resolveThemeMode(nextMode));
                if (!mounted) return;
                Snack.show(
                  context,
                  context.l10n.themeSet(_themeLabel(nextMode)),
                  level: SnackLevel.success,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyOptionsCard(
    BuildContext context,
    ThemeData theme,
    bool playAdMode,
  ) {
    return FutureBuilder<PrivacyOptionsRequirementStatus>(
      future: ConsentInformation.instance.getPrivacyOptionsRequirementStatus(),
      builder: (context, snapshot) {
        // Only show privacy options if required by UMP (EU/EEA users)
        if (snapshot.data != PrivacyOptionsRequirementStatus.required) {
          return const SizedBox.shrink();
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.adPreferences,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.manageAdPersonalisationConsent,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.settings),
                  label: Text(context.l10n.manageAdPreferences),
                  onPressed: () {
                    ConsentForm.showPrivacyOptionsForm((formError) {
                      if (formError != null) {
                        debugPrint(
                            'Privacy options error: ${formError.message}');
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _watchAdForTemporaryAdPause() async {
    if (_isRunningAdAction) return;
    AdService.instance.registerInteraction();
    setState(() => _isRunningAdAction = true);
    final rewardEarned =
        await AdService.instance.showRewardedAdForTemporaryAdBreak();
    if (!mounted) return;
    setState(() {
      _isRunningAdAction = false;
      _adsWatchedCount = AdService.instance.adsWatchedCount;
    });

    if (rewardEarned) {
      Snack.show(
        context,
        context.l10n.adsOffFor30MinutesThanks,
        level: SnackLevel.success,
      );
    } else {
      Snack.show(
        context,
        context.l10n.noRewardRecordedAdsStayOn,
        level: SnackLevel.info,
      );
    }
  }

  Future<void> _watchAdToSupportWithoutAdPause() async {
    if (_isRunningAdAction) return;
    AdService.instance.registerInteraction();
    setState(() => _isRunningAdAction = true);
    final rewardEarned =
        await AdService.instance.showRewardedAdToSupportProject();
    if (!mounted) return;
    setState(() {
      _isRunningAdAction = false;
      _adsWatchedCount = AdService.instance.adsWatchedCount;
    });

    if (rewardEarned) {
      Snack.show(
        context,
        context.l10n.thanksForSupportAdsStayOn,
        level: SnackLevel.success,
      );
    } else {
      Snack.show(
        context,
        context.l10n.noRewardRecordedTryAgain,
        level: SnackLevel.info,
      );
    }
  }

  String _favouriteDedupKey(String rawPath) {
    final value = rawPath.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return 'url:${value.toLowerCase()}';
    }
    if (value.startsWith('content://')) {
      return 'id:${value.toLowerCase()}';
    }
    final normalised = Platform.isWindows ? value.toLowerCase() : value;
    return 'path:$normalised';
  }

  bool _isValidFavouritePath(String rawPath) {
    final value = rawPath.trim();
    if (value.isEmpty) return false;
    if (value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('content://')) {
      return true;
    }
    return File(value).existsSync();
  }

  Future<void> _cleanupPlayerFavourites() async {
    final prefs = await SharedPreferences.getInstance();
    final favourites = prefs.getStringList('player_favourites') ?? const [];

    final dedup = <String>{};
    final cleaned = <String>[];
    for (final path in favourites) {
      if (!_isValidFavouritePath(path)) continue;
      final key = _favouriteDedupKey(path);
      if (dedup.add(key)) cleaned.add(path.trim());
    }

    final cleanedSet = cleaned.toSet();
    final rawCache = prefs.getStringList('player_favourites_cache') ?? const [];
    final nextCache = <String>[];
    final cacheSeen = <String>{};
    for (final row in rawCache) {
      final parts = row.split('\t');
      if (parts.length < 2) continue;
      final path = parts[0].trim();
      if (!cleanedSet.contains(path)) continue;
      final key = _favouriteDedupKey(path);
      if (!cacheSeen.add(key)) continue;
      nextCache.add(row);
    }

    await prefs.setStringList('player_favourites', cleaned..sort());
    await prefs.setStringList('player_favourites_cache', nextCache);

    final removed = favourites.length - cleaned.length;
    if (!mounted) return;
    Snack.show(
      context,
      removed > 0
          ? context.l10n.favouritesCleanedRemovedInvalidDuplicate(removed)
          : context.l10n.noInvalidDuplicateFavouritesFound,
      level: SnackLevel.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final purchase = context.watch<PurchaseService>();
    final controller = context.watch<AppController>();
    final adService = AdService.instance;
    final hasAdBreak = adService.hasTemporaryAdBreak;
    final adBreakRemaining = adService.temporaryAdBreakRemaining;
    final playAdMode = kPlayStoreBuild;
    final adActionsEnabled =
        !purchase.isAdFree && playAdMode && adService.adsAvailable;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.support(getAppTitle()),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.ifEnjoyUsingBestWay(getAppTitle()),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.adsWatchedBySupporters(_adsWatchedCount),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasAdBreak) ...[
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      key: ValueKey(_formatDuration(adBreakRemaining)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        context.l10n.adsPausedRemaining(_formatDuration(adBreakRemaining)),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.removeAds,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  purchase.isAdFree
                      ? context.l10n.adsAlreadyRemovedDevice
                      : context.l10n.oneTimeUnlockSuppressesEvery,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      icon: Icon(
                        purchase.isAdFree ? Icons.verified : Icons.block,
                      ),
                      label: Text(
                        purchase.isAdFree
                            ? context.l10n.adsRemoved
                            : context.l10n.removeAds2(purchase.removeAdsPriceLabel),
                      ),
                      onPressed: purchase.storeAvailable && !purchase.isAdFree
                          ? _buyRemoveAds
                          : null,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.restore),
                      label: Text(context.l10n.restorePurchase),
                      onPressed:
                          purchase.storeAvailable ? _restorePurchases : null,
                    ),
                  ],
                ),
                if (!purchase.storeAvailable)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      context.l10n.purchasesOnlyAvailableAndroidPlay,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildAppearanceCard(theme, controller),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.playerFavourites2,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.removeGhostEntriesDeduplicateFavourites,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _cleanupPlayerFavourites,
                  icon: const Icon(Icons.cleaning_services),
                  label: Text(context.l10n.cleanUpFavourites),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildPrivacyOptionsCard(context, theme, playAdMode),
        const SizedBox(height: 12),
        if (!purchase.isAdFree && playAdMode) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.goodwillSupportAds,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.noFakePromisesTheseActions,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: adActionsEnabled && !_isRunningAdAction
                            ? _watchAdForTemporaryAdPause
                            : null,
                        icon: _isRunningAdAction
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.pause_circle_filled),
                        label: Text(context.l10n.turnAdsOff30Min),
                      ),
                      OutlinedButton.icon(
                        onPressed: adActionsEnabled && !_isRunningAdAction
                            ? _watchAdToSupportWithoutAdPause
                            : null,
                        icon: const Icon(Icons.favorite),
                        label: Text(context.l10n.supportMeAdsStay),
                      ),
                    ],
                  ),
                  if (!adActionsEnabled) ...[
                    const SizedBox(height: 8),
                    Text(
                      hasAdBreak
                          ? context.l10n.adPauseActiveRewardedAds
                          : context.l10n.rewardedAdsCurrentlyUnavailable,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (!purchase.isAdFree) ...[
          const WatchAdCard(),
          const SizedBox(height: 16),
        ],
        Card(
          child: ListTile(
            leading: const Icon(Icons.play_circle_fill, color: Colors.red),
            title: Text(context.l10n.watchDemoVideo),
            subtitle: Text(context.l10n.quickTourAppYoutube),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openUrl('https://youtu.be/66Rx8PDY_r0'),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.coffee, color: Colors.brown),
            title: Text(context.l10n.buyMeCoffee),
            subtitle: Text(context.l10n.helpKeepProjectFreeOpen),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openUrl('https://buymeacoffee.com/orokaconner'),
          ),
        ),
        const SizedBox(height: 12),
        if (kPlayStoreBuild)
          Card(
            child: ListTile(
              leading: Icon(Icons.open_in_browser,
                  color: Theme.of(context).colorScheme.primary),
              title: Text(context.l10n.advancedBuildGithub),
              subtitle:
                  Text(context.l10n.openSourceBuildAllFeatures),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openUrl(
                  'https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases'),
            ),
          ),
        if (kPlayStoreBuild) const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.favorite, color: Colors.pink),
            title: Text(context.l10n.githubSponsors),
            subtitle:
                Text(context.l10n.supportOngoingDevelopmentFeatureWork),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openUrl('https://github.com/sponsors/Lukas-Bohez'),
          ),
        ),
        const SizedBox(height: 12),
        if (!purchase.isAdFree && playAdMode) const AdBannerSlot(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.privacyFirst,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  kPlayStoreBuild
                      ? context.l10n.appDoesNotCollectAnalytics
                      : context.l10n.appDoesNotCollectAnalytics2,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
