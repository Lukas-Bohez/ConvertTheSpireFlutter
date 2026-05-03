import 'package:flutter/material.dart';
import 'colour_rarity.dart';
import 'colour_reward_service.dart';

class ColourCollectionGrid extends StatefulWidget {
  const ColourCollectionGrid({Key? key}) : super(key: key);

  @override
  State<ColourCollectionGrid> createState() => _ColourCollectionGridState();
}

class _ColourCollectionGridState extends State<ColourCollectionGrid> {
  @override
  void initState() {
    super.initState();
    ColourRewardService.instance.init().then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final all = kAllColours;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: all.length,
      itemBuilder: (context, idx) {
        final c = all[idx];
        final owned = ColourRewardService.instance.isOwned(c.id);
        final equipped = ColourRewardService.instance.equippedId == c.id;
        return GestureDetector(
          onTap: owned
              ? () async {
                  await ColourRewardService.instance.equipColour(c.id);
                  setState(() {});
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              color: c.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.rarity.glowColor.withOpacity(0.6)),
            ),
            child: Stack(children: [
              Center(child: Text(c.displayName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
              if (!owned)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.45),
                    child: const Center(child: Icon(Icons.lock, color: Colors.white70)),
                  ),
                ),
              if (equipped)
                const Positioned(top: 4, right: 4, child: Icon(Icons.check_circle, color: Colors.white70, size: 18)),
            ]),
          ),
        );
      },
    );
  }
}
