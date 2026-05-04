import 'package:flutter/material.dart';
import '../../services/ad_service.dart';
import 'colour_rarity.dart';
import 'colour_reward_service.dart';

class ColourRevealDialog extends StatefulWidget {
  const ColourRevealDialog({Key? key, required this.reward}) : super(key: key);
  final ColourReward reward;

  @override
  State<ColourRevealDialog> createState() => _ColourRevealDialogState();
}

class _ColourRevealDialogState extends State<ColourRevealDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reward = widget.reward;
    final owned = ColourRewardService.instance.isOwned(reward.id);
    final equipped = ColourRewardService.instance.equippedId == reward.id;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: FadeTransition(
        opacity: _ctrl.drive(Tween(begin: 0.0, end: 1.0)),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Theme.of(context).dialogTheme.backgroundColor ??
                  Theme.of(context).colorScheme.surface,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                decoration: reward.rarity.cardDecoration,
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  CircleAvatar(radius: 40, backgroundColor: reward.color),
                  const SizedBox(height: 12),
                  Text(reward.displayName, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Chip(label: Text(reward.rarity.label)),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                if (!owned)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        AdService.instance.registerInteraction();
                        await ColourRewardService.instance.unlockColour(reward.id);
                        await ColourRewardService.instance.equipColour(reward.id);
                        if (!mounted) return;
                        Navigator.of(context).pop(true);
                      },
                      child: const Text('Equip'),
                    ),
                  )
                else
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        equipped ? 'Already equipped' : 'Already in your collection',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                if (!owned) const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      AdService.instance.registerInteraction();
                      Navigator.of(context).pop(false);
                    },
                    child: const Text('Close'),
                  ),
                ),
              ])
            ]),
          ),
        ),
      ),
    );
  }
}
