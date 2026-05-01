import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../config/build_flags.dart';
import '../services/ad_service.dart';
import '../services/purchase_service.dart';
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

  @override
  void initState() {
    super.initState();
    PurchaseService.instance.addListener(_handlePurchaseChanged);
  }

  @override
  void dispose() {
    PurchaseService.instance.removeListener(_handlePurchaseChanged);
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

  Future<void> _watchRewardedAd() async {
    final shown = await AdService.instance.showRewardedAdForQueueBoost(
      boostDuration: const Duration(minutes: 30),
    );
    if (!mounted) return;
    if (shown) {
      Snack.show(context, '30-minute queue boost activated.',
          level: SnackLevel.success);
    } else {
      Snack.show(context, 'No rewarded ad was available right now.',
          level: SnackLevel.error);
    }
  }

  Future<void> _watchRewardedInterstitialAd() async {
    final shown = await AdService.instance.showRewardedInterstitialForQueueBoost(
      boostDuration: const Duration(hours: 24),
    );
    if (!mounted) return;
    if (shown) {
      Snack.show(context, '24-hour queue boost activated.',
          level: SnackLevel.success);
    } else {
      Snack.show(context, 'No rewarded interstitial was available right now.',
          level: SnackLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final purchase = context.watch<PurchaseService>();

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
        if (!purchase.isAdFree) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.flash_on, color: Colors.orange),
              title: const Text('Watch Ad for Queue Boost'),
              subtitle: const Text('Earn 30 minutes of extra queue capacity'),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: _watchRewardedAd,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium, color: Colors.amber),
              title: const Text('Watch Premium Ad for 24h Boost'),
              subtitle: const Text('Best for large batch download sessions'),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: _watchRewardedInterstitialAd,
            ),
          ),
          const SizedBox(height: 16),
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
