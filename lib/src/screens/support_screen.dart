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
        const SnackBar(content: Text('Remove Ads unlocked. All ads are off.')),
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
        Snack.show(context, 'Could not launch $url', level: SnackLevel.error);
      }
    }
  }

  Future<void> _buyRemoveAds() async {
    AdService.instance.registerInteraction();
    final purchase = PurchaseService.instance;
    if (!purchase.storeAvailable) {
      Snack.show(
        context,
        'Remove Ads purchases are only available on Android Play builds.',
        level: SnackLevel.error,
      );
      return;
    }

    await purchase.purchaseRemoveAds();
    if (mounted) {
      Snack.show(
        context,
        'Opening the Play purchase flow…',
        level: SnackLevel.info,
      );
    }
  }

  Future<void> _restorePurchases() async {
    AdService.instance.registerInteraction();
    await PurchaseService.instance.restorePurchases();
    if (mounted) {
      Snack.show(context, 'Restore request sent.', level: SnackLevel.info);
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
        return 'Light';
      case 'dark':
        return 'Dark';
      default:
        return 'System';
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
                  'Appearance',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the app theme used across the desktop and mobile UI.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'system',
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: 'light',
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: 'dark',
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {currentMode},
              onSelectionChanged: (value) async {
                final nextMode = value.first;
                await controller.setThemeMode(_resolveThemeMode(nextMode));
                if (!mounted) return;
                Snack.show(
                  context,
                  'Theme set to ${_themeLabel(nextMode)}',
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
                  'Ad Preferences',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage your ad personalisation consent.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.settings),
                  label: const Text('Manage Ad Preferences'),
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
        'Dankjewel! Advertenties staan 30 minuten uit.',
        level: SnackLevel.success,
      );
    } else {
      Snack.show(
        context,
        'Geen reward geregistreerd. Advertenties blijven aan.',
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
        'Top! Bedankt voor je support. Advertenties blijven aan.',
        level: SnackLevel.success,
      );
    } else {
      Snack.show(
        context,
        'Geen reward geregistreerd. Probeer opnieuw als je wil supporten.',
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
          ? 'Favourites cleaned: removed $removed invalid or duplicate entries.'
          : 'No invalid or duplicate favourites found.',
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
                  'Support ${getAppTitle()}',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'If you enjoy using ${getAppTitle()}, the best way to support continued development is via donations or the one-time Remove Ads unlock.',
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
                          'Ads watched by supporters: $_adsWatchedCount',
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
                        'Ads paused: ${_formatDuration(adBreakRemaining)} remaining',
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
                  'Remove Ads',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  purchase.isAdFree
                      ? 'Ads are already removed on this device.'
                      : 'One-time unlock that suppresses every ad placement in the app.',
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
                            ? 'Ads removed'
                            : 'Remove Ads — ${purchase.removeAdsPriceLabel}',
                      ),
                      onPressed: purchase.storeAvailable && !purchase.isAdFree
                          ? _buyRemoveAds
                          : null,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.restore),
                      label: const Text('Restore Purchase'),
                      onPressed:
                          purchase.storeAvailable ? _restorePurchases : null,
                    ),
                  ],
                ),
                if (!purchase.storeAvailable)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Purchases are only available on Android Play builds.',
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
                  'Player Favourites',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Remove ghost entries and deduplicate favourites by path, URL, or content id.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _cleanupPlayerFavourites,
                  icon: const Icon(Icons.cleaning_services),
                  label: const Text('Clean Up Favourites'),
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
                    'Goodwill Support Ads',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No fake promises: these actions are exactly what they claim.',
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
                        label: const Text('Turn ads off for 30 min'),
                      ),
                      OutlinedButton.icon(
                        onPressed: adActionsEnabled && !_isRunningAdAction
                            ? _watchAdToSupportWithoutAdPause
                            : null,
                        icon: const Icon(Icons.favorite),
                        label: const Text('Support me (ads stay on)'),
                      ),
                    ],
                  ),
                  if (!adActionsEnabled) ...[
                    const SizedBox(height: 8),
                    Text(
                      hasAdBreak
                          ? 'Ad pause active. Rewarded ads are temporarily hidden.'
                          : 'Rewarded ads are currently unavailable.',
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
            leading: const Icon(Icons.coffee, color: Colors.brown),
            title: const Text('Buy Me a Coffee'),
            subtitle: const Text('Help keep this project free & open-source'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openUrl('https://buymeacoffee.com/orokaconner'),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.favorite, color: Colors.pink),
            title: const Text('GitHub Sponsors'),
            subtitle:
                const Text('Support ongoing development and feature work'),
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
                  'Privacy First',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This app does not collect analytics or track what you download. All processing happens locally on your device.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
