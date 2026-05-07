import 'package:convert_the_spire_reborn/src/features/colour_rewards/colour_rarity.dart';
import 'package:convert_the_spire_reborn/src/features/colour_rewards/colour_reward_session_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<ColourReward> _manyCommonRewards() {
  return const [
    ColourReward(id: 'c1', displayName: 'Common 1', color: Color(0xFF4B5B6A), rarity: RarityTier.common),
    ColourReward(id: 'c2', displayName: 'Common 2', color: Color(0xFF2F4F57), rarity: RarityTier.common),
    ColourReward(id: 'c3', displayName: 'Common 3', color: Color(0xFF263238), rarity: RarityTier.common),
    ColourReward(id: 'c4', displayName: 'Common 4', color: Color(0xFF90A4AE), rarity: RarityTier.common),
    ColourReward(id: 'c5', displayName: 'Common 5', color: Color(0xFF8A9BA7), rarity: RarityTier.common),
    ColourReward(id: 'c6', displayName: 'Common 6', color: Color(0xFF607D8B), rarity: RarityTier.common),
    ColourReward(id: 'c7', displayName: 'Common 7', color: Color(0xFF546E7A), rarity: RarityTier.common),
    ColourReward(id: 'c8', displayName: 'Common 8', color: Color(0xFF455A64), rarity: RarityTier.common),
    ColourReward(id: 'c9', displayName: 'Common 9', color: Color(0xFF37474F), rarity: RarityTier.common),
    ColourReward(id: 'c10', displayName: 'Common 10', color: Color(0xFF263238), rarity: RarityTier.common),
  ];
}

void main() {
  testWidgets('Colour reward summary scrolls and keeps the claim button reachable',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ColourRewardSessionDialog(rewards: _manyCommonRewards()),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final nextFinder = find.text('Next');
    for (var i = 0; i < 20; i++) {
      expect(nextFinder, findsOneWidget);
      await tester.tap(nextFinder);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      if (find.text('Claim').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.text('Claim'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
