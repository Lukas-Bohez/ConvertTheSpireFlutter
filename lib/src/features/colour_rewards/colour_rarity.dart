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
    color: glowColor.withValues(alpha: 0.08),
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
  // Common — tuned to be visually distinct (different hue/saturation)
  ColourReward(id: 'slate',        displayName: 'Slate',        color: Color(0xFF4B5B6A), rarity: RarityTier.common),
  ColourReward(id: 'steel',        displayName: 'Steel',        color: Color(0xFF2F4F57), rarity: RarityTier.common),
  ColourReward(id: 'graphite',     displayName: 'Graphite',     color: Color(0xFF263238), rarity: RarityTier.common),
  ColourReward(id: 'mist',         displayName: 'Mist',         color: Color(0xFF90A4AE), rarity: RarityTier.common),
  ColourReward(id: 'ash',          displayName: 'Ash',          color: Color(0xFF8A9BA7), rarity: RarityTier.common),
  // Uncommon
  // Uncommon — stronger contrasts and saturation
  ColourReward(id: 'ocean_blue',   displayName: 'Ocean Blue',   color: Color(0xFF0077CC), rarity: RarityTier.uncommon),
  ColourReward(id: 'deep_teal',    displayName: 'Deep Teal',    color: Color(0xFF00796B), rarity: RarityTier.uncommon),
  ColourReward(id: 'indigo',       displayName: 'Indigo',       color: Color(0xFF3F1F8A), rarity: RarityTier.uncommon),
  ColourReward(id: 'burnt_sienna', displayName: 'Burnt Sienna', color: Color(0xFFBF4A00), rarity: RarityTier.uncommon),
  ColourReward(id: 'bark',         displayName: 'Bark',         color: Color(0xFF5D3526), rarity: RarityTier.uncommon),
  // Rare
  // Rare — vivid and unique
  ColourReward(id: 'ruby',         displayName: 'Ruby',         color: Color(0xFFB71C1C), rarity: RarityTier.rare),
  ColourReward(id: 'berry',        displayName: 'Berry',        color: Color(0xFF9C1850), rarity: RarityTier.rare),
  ColourReward(id: 'cyan_depth',   displayName: 'Cyan Depth',   color: Color(0xFF007B8A), rarity: RarityTier.rare),
  ColourReward(id: 'fern',         displayName: 'Fern',         color: Color(0xFF2E7D32), rarity: RarityTier.rare),
  ColourReward(id: 'saffron',      displayName: 'Saffron',      color: Color(0xFFF57C00), rarity: RarityTier.rare),
  // Epic
  // Epic — deeper tones with character
  ColourReward(id: 'void_purple',  displayName: 'Void Purple',  color: Color(0xFF5E2A8A), rarity: RarityTier.epic),
  ColourReward(id: 'crimson_rose', displayName: 'Crimson Rose', color: Color(0xFFC2185B), rarity: RarityTier.epic),
  ColourReward(id: 'abyss',        displayName: 'Abyss',        color: Color(0xFF004D54), rarity: RarityTier.epic),
  ColourReward(id: 'forest_king',  displayName: 'Forest King',  color: Color(0xFF145A32), rarity: RarityTier.epic),
  ColourReward(id: 'ember',        displayName: 'Ember',        color: Color(0xFFD84315), rarity: RarityTier.epic),
  // Legendary
  // Legendary — bold & recognizable
  ColourReward(id: 'dark_gold',    displayName: 'Dark Gold',    color: Color(0xFFB8860B), rarity: RarityTier.legendary),
  ColourReward(id: 'royal_amethyst',displayName: 'Royal Amethyst',color: Color(0xFF6A1B9A), rarity: RarityTier.legendary),
  ColourReward(id: 'dragon_teal',  displayName: 'Dragon Teal',  color: Color(0xFF007A7A), rarity: RarityTier.legendary),
  ColourReward(id: 'wine_crest',   displayName: 'Wine Crest',   color: Color(0xFF7B2C2C), rarity: RarityTier.legendary),
  // Mythic
  // Mythic — extreme contrast and uniqueness
  ColourReward(id: 'mythic_red',        displayName: 'Mythic Red',         color: Color(0xFFE53935), rarity: RarityTier.mythic),
  ColourReward(id: 'mango_passion',     displayName: 'Mango Passion',      color: Color(0xFFFFA726), rarity: RarityTier.mythic),
  ColourReward(id: 'obsidian_black',    displayName: 'Obsidian Black',     color: Color(0xFF0D0D0D), rarity: RarityTier.mythic),
  ColourReward(id: 'ivory_prime',       displayName: 'Ivory Prime',        color: Color(0xFFF2E8D5), rarity: RarityTier.mythic),
];
