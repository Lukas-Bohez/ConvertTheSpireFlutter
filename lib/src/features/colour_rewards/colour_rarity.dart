import 'package:flutter/material.dart';

enum RarityTier { common, uncommon, rare, epic, legendary, mythic }

extension RarityTierX on RarityTier {
  String get label => name[0].toUpperCase() + name.substring(1);

  Color get glowColor => const {
    RarityTier.common:    Color(0xFF607D8B),
    RarityTier.uncommon:  Color(0xFF1565C0),
    RarityTier.rare:      Color(0xFFC62828),
    RarityTier.epic:      Color(0xFF4A148C),
    RarityTier.legendary: Color(0xFFB8860B),
    RarityTier.mythic:    Color(0xFFCC1100),
  }[this]!;

  /// Border decoration for the reveal card
  BoxDecoration get cardDecoration => BoxDecoration(
    border: Border.all(color: glowColor, width: rarityBorderWidth),
    borderRadius: BorderRadius.circular(16),
    color: glowColor.withOpacity(0.08),
  );

  double get rarityBorderWidth => switch (this) {
    RarityTier.common    => 1.0,
    RarityTier.uncommon  => 1.5,
    RarityTier.rare      => 2.0,
    RarityTier.epic      => 2.5,
    RarityTier.legendary => 3.0,
    RarityTier.mythic    => 3.5,
  };
}

class ColourReward {
  const ColourReward({
    required this.id,
    required this.displayName,
    required this.color,
    required this.rarity,
  });

  final String id;
  final String displayName;
  final Color color;
  final RarityTier rarity;
}

const List<ColourReward> kAllColours = [
  // Common
  ColourReward(id: 'slate',        displayName: 'Slate',        color: Color(0xFF607D8B), rarity: RarityTier.common),
  ColourReward(id: 'steel',        displayName: 'Steel',        color: Color(0xFF455A64), rarity: RarityTier.common),
  ColourReward(id: 'graphite',     displayName: 'Graphite',     color: Color(0xFF37474F), rarity: RarityTier.common),
  ColourReward(id: 'mist',         displayName: 'Mist',         color: Color(0xFF78909C), rarity: RarityTier.common),
  ColourReward(id: 'ash',          displayName: 'Ash',          color: Color(0xFF546E7A), rarity: RarityTier.common),
  // Uncommon
  ColourReward(id: 'ocean_blue',   displayName: 'Ocean Blue',   color: Color(0xFF1565C0), rarity: RarityTier.uncommon),
  ColourReward(id: 'deep_teal',    displayName: 'Deep Teal',    color: Color(0xFF00695C), rarity: RarityTier.uncommon),
  ColourReward(id: 'indigo',       displayName: 'Indigo',       color: Color(0xFF6A1B9A), rarity: RarityTier.uncommon),
  ColourReward(id: 'burnt_sienna', displayName: 'Burnt Sienna', color: Color(0xFFE65100), rarity: RarityTier.uncommon),
  ColourReward(id: 'bark',         displayName: 'Bark',         color: Color(0xFF4E342E), rarity: RarityTier.uncommon),
  // Rare
  ColourReward(id: 'ruby',         displayName: 'Ruby',         color: Color(0xFFC62828), rarity: RarityTier.rare),
  ColourReward(id: 'berry',        displayName: 'Berry',        color: Color(0xFFAD1457), rarity: RarityTier.rare),
  ColourReward(id: 'cyan_depth',   displayName: 'Cyan Depth',   color: Color(0xFF00838F), rarity: RarityTier.rare),
  ColourReward(id: 'fern',         displayName: 'Fern',         color: Color(0xFF558B2F), rarity: RarityTier.rare),
  ColourReward(id: 'saffron',      displayName: 'Saffron',      color: Color(0xFFF57F17), rarity: RarityTier.rare),
  // Epic
  ColourReward(id: 'void_purple',  displayName: 'Void Purple',  color: Color(0xFF4A148C), rarity: RarityTier.epic),
  ColourReward(id: 'crimson_rose', displayName: 'Crimson Rose', color: Color(0xFF880E4F), rarity: RarityTier.epic),
  ColourReward(id: 'abyss',        displayName: 'Abyss',        color: Color(0xFF006064), rarity: RarityTier.epic),
  ColourReward(id: 'forest_king',  displayName: 'Forest King',  color: Color(0xFF1B5E20), rarity: RarityTier.epic),
  ColourReward(id: 'ember',        displayName: 'Ember',        color: Color(0xFFBF360C), rarity: RarityTier.epic),
  // Legendary
  ColourReward(id: 'dark_gold',    displayName: 'Dark Gold',    color: Color(0xFFB8860B), rarity: RarityTier.legendary),
  ColourReward(id: 'royal_amethyst',displayName: 'Royal Amethyst',color: Color(0xFF4B0082), rarity: RarityTier.legendary),
  ColourReward(id: 'dragon_teal',  displayName: 'Dragon Teal',  color: Color(0xFF008080), rarity: RarityTier.legendary),
  ColourReward(id: 'wine_crest',   displayName: 'Wine Crest',   color: Color(0xFF722F37), rarity: RarityTier.legendary),
  // Mythic
  ColourReward(id: 'mythic_red',        displayName: 'Mythic Red',         color: Color(0xFFCC1100), rarity: RarityTier.mythic),
  ColourReward(id: 'mango_passion',     displayName: 'Mango Passion',      color: Color(0xFFFFB347), rarity: RarityTier.mythic),
  ColourReward(id: 'obsidian_black',    displayName: 'Obsidian Black',     color: Color(0xFF0A0A0A), rarity: RarityTier.mythic),
  ColourReward(id: 'ivory_prime',       displayName: 'Ivory Prime',        color: Color(0xFFE8D5B7), rarity: RarityTier.mythic),
];
