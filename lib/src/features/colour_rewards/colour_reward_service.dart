import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/build_flags.dart';
import 'colour_rarity.dart';

class ColourRewardService extends ChangeNotifier {
  ColourRewardService._();
  static final ColourRewardService _instance = ColourRewardService._();
  static ColourRewardService get instance => _instance;

  static const String _ownedKey = 'colour_rewards_owned';
  static const String _equippedKey = 'colour_rewards_equipped';
  static const String _allPurchasedKey = 'colour_all_purchased';
  static const String _lastFreeSpinKey = 'colour_last_free_spin_day';

  final Set<String> _owned = {};
  String _equipped = 'slate';
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final ownedJson = prefs.getString(_ownedKey);
    if (ownedJson != null && ownedJson.isNotEmpty) {
      try {
        final list = jsonDecode(ownedJson) as List<dynamic>;
        _owned.addAll(list.cast<String>());
      } catch (_) {}
    }
    final eq = prefs.getString(_equippedKey);
    if (eq != null && eq.isNotEmpty) _equipped = eq;

    // GitHub release builds unlock all colours from install
    if (kIsGithubRelease) {
      await unlockAllColours();
    } else {
      // Ensure slate owned on first run (normal builds)
      if (_owned.isEmpty) {
        _owned.add('slate');
        await prefs.setString(_ownedKey, jsonEncode(_owned.toList()));
      }

      if (prefs.getBool(_allPurchasedKey) ?? false) {
        await unlockAllColours();
      }
    }

    _initialized = true;
    notifyListeners();
  }

  List<ColourReward> get ownedRewards =>
      kAllColours.where((c) => _owned.contains(c.id)).toList();

  bool isOwned(String id) => _owned.contains(id);

  String get equippedId => _equipped;

  ColourReward get equipped => kAllColours.firstWhere((c) => c.id == _equipped,
      orElse: () => kAllColours.first);

  /// Takes today's free spin: false when it was already taken today.
  ///
  /// The Microsoft Store build has no ads to pay for spins (Android's
  /// way), so it gives one free spin a day, and sells all colours at once
  /// as a Store add-on.
  Future<bool> takeDailyFreeSpin({DateTime? now}) async {
    final today = _day(now ?? DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_lastFreeSpinKey) == today) return false;
    await prefs.setString(_lastFreeSpinKey, today);
    return true;
  }

  static String _day(DateTime time) =>
      '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';

  Future<void> unlockColour(String id) async {
    if (_owned.add(id)) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ownedKey, jsonEncode(_owned.toList()));
      notifyListeners();
    }
  }

  Future<void> unlockAllColours() async {
    for (final colour in kAllColours) {
      _owned.add(colour.id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownedKey, jsonEncode(_owned.toList()));
    await prefs.setBool(_allPurchasedKey, true);
    notifyListeners();
  }

  Future<void> equipColour(String id) async {
    if (!_owned.contains(id)) return;
    _equipped = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_equippedKey, _equipped);
    notifyListeners();
  }

  /// Utility used by the Watch Ad flow to randomly pick a colour based on rarities.
  ColourReward rollReward() {
    // Build a weighted list
    final List<ColourReward> pool = [];
    for (final c in kAllColours) {
      final weight = switch (c.rarity) {
        RarityTier.common => 60,
        RarityTier.uncommon => 20,
        RarityTier.rare => 10,
        RarityTier.epic => 6,
        RarityTier.legendary => 3,
        RarityTier.mythic => 1,
      };
      for (int i = 0; i < weight; i++) {
        pool.add(c);
      }
    }
    pool.shuffle();
    return pool.first;
  }
}
