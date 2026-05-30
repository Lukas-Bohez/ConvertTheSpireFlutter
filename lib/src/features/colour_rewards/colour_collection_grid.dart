import 'package:flutter/material.dart';

import '../../services/ad_service.dart';
import 'colour_rarity.dart';
import 'colour_reward_service.dart';

class ColourCollectionGrid extends StatefulWidget {
  const ColourCollectionGrid({
    super.key,
    this.scrollController,
  });

  final ScrollController? scrollController;

  @override
  State<ColourCollectionGrid> createState() => _ColourCollectionGridState();
}

class _ColourCollectionGridState extends State<ColourCollectionGrid> {
  @override
  void initState() {
    super.initState();
    ColourRewardService.instance.init().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final owned = ColourRewardService.instance;
    final bottomInset = MediaQuery.of(context).padding.bottom + 96;
    final themeColours = {
      for (final tier in RarityTier.values)
        tier: kAllColours.where((c) => c.rarity == tier).toList(),
    };
    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        AdService.instance.registerInteraction();
        return false;
      },
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset),
        children: [
          for (final tier in RarityTier.values) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                tier.label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: themeColours[tier]!.length,
              itemBuilder: (context, index) {
                final c = themeColours[tier]![index];
                final isOwned = owned.isOwned(c.id);
                final equipped = owned.equippedId == c.id;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: isOwned
                        ? () async {
                            AdService.instance.registerInteraction();
                            await ColourRewardService.instance
                                .equipColour(c.id);
                            if (mounted) setState(() {});
                          }
                        : null,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: c.rarity.glowColor.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Text(
                              c.displayName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          if (!isOwned)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.45),
                                child: const Center(
                                  child:
                                      Icon(Icons.lock, color: Colors.white70),
                                ),
                              ),
                            ),
                          if (equipped)
                            const Positioned(
                              top: 4,
                              right: 4,
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.white70,
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
