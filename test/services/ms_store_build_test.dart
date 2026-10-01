import 'package:convert_the_spire_reborn/src/features/colour_rewards/colour_reward_service.dart';
import 'package:convert_the_spire_reborn/src/services/bundled_tools.dart';
import 'package:convert_the_spire_reborn/src/services/ms_store_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Microsoft Store build's own parts that can be tested off Windows.
void main() {
  group('BundledTools', () {
    test('finds programs in folders next to the exe', () {
      const exe = r'C:\Program Files\WindowsApps\Pkg_15.2.0.0_x64__abc'
          r'\convert_the_spire_reborn.exe';
      expect(
          BundledTools.pathOf('ffmpeg', 'ffmpeg.exe',
              executable: exe, windows: true),
          r'C:\Program Files\WindowsApps\Pkg_15.2.0.0_x64__abc'
          r'\ffmpeg\ffmpeg.exe');
      expect(
          BundledTools.pathOf('deno', 'deno.exe',
              executable: exe, windows: true),
          endsWith(r'__abc\deno\deno.exe'));
    });

    test('none off Windows', () {
      expect(
          BundledTools.pathOf('ffmpeg', 'ffmpeg.exe',
              executable: '/opt/app/app', windows: false),
          isNull);
    });
  });

  group('MsStoreService', () {
    test('reads an add-on from the Store', () {
      final addOn = MsStoreAddOn.fromMap({
        'storeId': '9NBLGGH4R315',
        'token': 'get_all_themes',
        'title': 'All colours',
        'price': '€2,99',
        'owned': true,
      })!;
      expect(addOn.storeId, '9NBLGGH4R315');
      expect(addOn.token, 'get_all_themes');
      expect(addOn.price, '€2,99');
      expect(addOn.owned, isTrue);
      expect(MsStoreAddOn.fromMap({'token': 'x'}), isNull);
      expect(MsStoreAddOn.fromMap('nonsense'), isNull);
    });

    test('purchase answers', () {
      expect(MsStoreService.parsePurchaseStatus('succeeded'),
          MsStorePurchaseStatus.succeeded);
      expect(MsStoreService.parsePurchaseStatus('alreadyPurchased'),
          MsStorePurchaseStatus.alreadyPurchased);
      expect(MsStoreService.parsePurchaseStatus('notPurchased'),
          MsStorePurchaseStatus.notPurchased);
      expect(MsStoreService.parsePurchaseStatus(null),
          MsStorePurchaseStatus.failed);
    });

    test('is not there outside the Store build', () async {
      expect(MsStoreService.supported, isFalse);
      expect(await MsStoreService.isAvailable(), isFalse);
      expect(await MsStoreService.addOns(), isEmpty);
    });
  });

  test('one free colour spin a day', () async {
    SharedPreferences.setMockInitialValues({});
    final colours = ColourRewardService.instance;
    final morning = DateTime(2026, 10, 1, 9);
    expect(await colours.takeDailyFreeSpin(now: morning), isTrue);
    expect(
        await colours.takeDailyFreeSpin(
            now: morning.add(const Duration(hours: 14))),
        isFalse);
    expect(await colours.takeDailyFreeSpin(now: DateTime(2026, 10, 2, 0, 1)),
        isTrue);
  });
}
