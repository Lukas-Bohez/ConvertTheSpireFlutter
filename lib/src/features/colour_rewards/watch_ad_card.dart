import 'package:flutter/material.dart';
import '../../services/ad_service.dart';
import 'colour_reward_service.dart';
import 'colour_reveal_dialog.dart';
import 'colour_collection_grid.dart';

class WatchAdCard extends StatefulWidget {
  const WatchAdCard({Key? key}) : super(key: key);

  @override
  State<WatchAdCard> createState() => _WatchAdCardState();
}

class _WatchAdCardState extends State<WatchAdCard> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    ColourRewardService.instance.init();
  }

  Future<void> _showAdAndReward() async {
    setState(() => _loading = true);
    final granted = await AdService.instance.showRewardedWithCustomReward(() async {
      final reward = ColourRewardService.instance.rollReward();
      await ColourRewardService.instance.unlockColour(reward.id);
      if (!mounted) return;
      await showDialog(context: context, builder: (_) => ColourRevealDialog(reward: reward));
    });
    if (!granted) {
      // noop: no reward granted
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Expanded(child: Text('Watch an ad → unlock a colour', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            TextButton(onPressed: () => showModalBottomSheet(context: context, builder: (_) => const SizedBox(height: 420, child: ColourCollectionGrid())), child: const Text('My collection'))
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            _oddsPill('Mythic', '1', Colors.redAccent),
            _oddsPill('Legendary', '3', Colors.amber),
            _oddsPill('Epic', '6', Colors.purple),
            _oddsPill('Rare', '10', Colors.red),
            _oddsPill('Uncommon', '20', Colors.blue),
            _oddsPill('Common', '60', Colors.grey),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.ondemand_video),
              label: const Text('Watch Ad'),
              onPressed: _loading ? null : _showAdAndReward,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _oddsPill(String label, String pct, Color c) => Chip(backgroundColor: c.withOpacity(0.12), label: Text('$label • $pct%'));
}
