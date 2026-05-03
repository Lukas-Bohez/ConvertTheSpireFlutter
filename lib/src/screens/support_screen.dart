import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../config/build_flags.dart';
import '../services/ad_service.dart';
import '../services/purchase_service.dart';
import '../utils/snack.dart';
import '../widgets/monetization_widgets.dart';
import '../features/colour_rewards/watch_ad_card.dart';

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
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        Snack.show(context, 'Could not launch $url', level: SnackLevel.error);
      }
    }
  }

  Future<void> _buyRemoveAds() async {
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
    await PurchaseService.instance.restorePurchases();
    if (mounted) {
      Snack.show(context, 'Restore request sent.', level: SnackLevel.info);
    }
  }

  Future<void> _watchAdForTemporaryAdPause() async {
    if (_isRunningAdAction) return;
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
    setState(() => _isRunningAdAction = true);
    final rewardEarned = await AdService.instance.showRewardedAdToSupportProject();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final purchase = context.watch<PurchaseService>();
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
                      onPressed: purchase.storeAvailable
                          ? _restorePurchases
                          : null,
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
        if (!playAdMode) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Ads are disabled in this build'),
              subtitle: const Text(
                'This is not a Play Store build, so rewarded ads are unavailable here.',
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
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
          const WatchAdCard(),
          const SizedBox(height: 8),
          const AdBannerSlot(),
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
