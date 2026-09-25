import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import 'package:convert_the_spire_reborn/src/services/ad_service.dart';
import 'package:convert_the_spire_reborn/src/services/purchase_service.dart';
import 'package:convert_the_spire_reborn/src/widgets/monetization_widgets.dart';

void main() {
  testWidgets('takes no room at all when ads cannot show', (tester) async {
    // Tests are not the Play build, the same as the GitHub builds and
    // Android TV: no ads, so the banner must not leave a gap or a spinner.
    expect(AdService.instance.adsReady, isFalse);

    await tester.pumpWidget(
      ChangeNotifierProvider<PurchaseService>.value(
        value: PurchaseService.instance,
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: Placeholder()),
                AdBannerSlot(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(tester.getSize(find.byType(AdBannerSlot)).height, 0);
    expect(find.byType(AdWidget), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
