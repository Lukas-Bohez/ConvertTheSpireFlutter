import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/build_flags.dart';
import '../../services/ad_service.dart';
import '../../services/purchase_service.dart';
import 'colour_collection_grid.dart';
import 'colour_rarity.dart';
import 'colour_reward_service.dart';
import 'colour_reward_session_dialog.dart';

class WatchAdCard extends StatefulWidget {
  const WatchAdCard({super.key});

  @override
  State<WatchAdCard> createState() => _WatchAdCardState();
}

class _WatchAdCardState extends State<WatchAdCard> {
  bool _loading = false;
  bool _buyingThemes = false;

  @override
  void initState() {
    super.initState();
    ColourRewardService.instance.init();
  }

  Future<List<ColourReward>> _rollBatch(int count) async {
    final rewards = <ColourReward>[];
    for (int i = 0; i < count; i++) {
      final reward = ColourRewardService.instance.rollReward();
      rewards.add(reward);
      await ColourRewardService.instance.unlockColour(reward.id);
    }
    return rewards;
  }

  Future<void> _showRewardSession(List<ColourReward> rewards) async {
    if (!mounted || rewards.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ColourRewardSessionDialog(rewards: rewards),
    );
  }

  Future<void> _showAdAndReward() async {
    AdService.instance.registerInteraction();
    setState(() => _loading = true);
    final granted =
        await AdService.instance.showRewardedWithCustomReward(() async {
      final rewards = await _rollBatch(10);
      await _showRewardSession(rewards);
    });
    if (!granted) {
      // noop: no reward granted
    }
    if (mounted) setState(() => _loading = false);
  }

  /// GitHub release builds allow free spins without ads.
  /// This method spins directly without requiring an ad watch.
  Future<void> _spinDirectly() async {
    AdService.instance.registerInteraction();
    setState(() => _loading = true);
    final rewards = await _rollBatch(10);
    await _showRewardSession(rewards);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _buyAllThemes() async {
    final purchase = PurchaseService.instance;
    if (!purchase.storeAvailable || purchase.hasAllThemes) return;
    AdService.instance.registerInteraction();
    setState(() => _buyingThemes = true);
    await purchase.purchaseAllThemes();
    if (!mounted) return;
    setState(() => _buyingThemes = false);
  }

  Future<void> _openCollection() async {
    AdService.instance.registerInteraction();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.68,
          minChildSize: 0.45,
          maxChildSize: 0.94,
          expand: false,
          builder: (sheetContext, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: ColourCollectionGrid(
                        scrollController: scrollController),
                  ),
                  SizedBox(
                      height: MediaQuery.of(sheetContext).padding.bottom + 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final purchase = context.watch<PurchaseService>();
    final hasAllThemes = purchase.hasAllThemes;
    final hasPrice = purchase.canPurchaseAllThemes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Expanded(
              child: Text(
                'Watch an ad → unlock a colour',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: _openCollection,
              child: const Text('My collection'),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            _oddsPill('Mythic', '0.1', Colors.redAccent),
            _oddsPill('Legendary', '1.9', Colors.amber),
            _oddsPill('Epic', '6', Colors.purple),
            _oddsPill('Rare', '12', Colors.red),
            _oddsPill('Uncommon', '25', Colors.blue),
            _oddsPill('Common', '55', Colors.grey),
          ]),
          const SizedBox(height: 12),
          if (hasAllThemes)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.45)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 10),
                  Text('All colours unlocked!'),
                ],
              ),
            )
          else ...[
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _buyingThemes ? null : _buyAllThemes,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB8860B), Color(0xFFCC1100)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.80),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 22, color: Color(0xFFB8860B)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Unlock All 28 Colours',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'One-time purchase · No ads needed',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              purchase.storeAvailable
                                  ? (hasPrice
                                      ? purchase.getAllThemesPriceLabel
                                      : 'Loading price…')
                                  : 'See price in store',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_buyingThemes)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(kIsGithubRelease
                        ? Icons.auto_awesome
                        : Icons.ondemand_video),
                label: const Text(kIsGithubRelease ? 'Spin for Colour' : 'Watch Ad'),
                onPressed: _loading
                    ? null
                    : (kIsGithubRelease ? _spinDirectly : _showAdAndReward),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _oddsPill(String label, String pct, Color c) => Chip(
      backgroundColor: c.withValues(alpha: 0.12),
      label: Text('$label • $pct%'));
}
