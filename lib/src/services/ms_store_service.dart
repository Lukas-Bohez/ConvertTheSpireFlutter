import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/build_flags.dart';

/// An add-on of the app in the Microsoft Store.
@immutable
class MsStoreAddOn {
  const MsStoreAddOn({
    required this.storeId,
    required this.token,
    required this.title,
    required this.price,
    required this.owned,
  });

  /// The Store's ID for it (9N...), which buying it takes.
  final String storeId;

  /// The product ID it was given in Partner Center, e.g. `get_all_themes`.
  final String token;
  final String title;

  /// Formatted in the user's currency, e.g. "€2,99".
  final String price;

  /// Whether this user has bought it.
  final bool owned;

  static MsStoreAddOn? fromMap(Object? value) {
    if (value is! Map) return null;
    final storeId = value['storeId'];
    if (storeId is! String || storeId.isEmpty) return null;
    return MsStoreAddOn(
      storeId: storeId,
      token: (value['token'] as String?) ?? '',
      title: (value['title'] as String?) ?? '',
      price: (value['price'] as String?) ?? '',
      owned: value['owned'] == true,
    );
  }
}

enum MsStorePurchaseStatus {
  succeeded,
  alreadyPurchased,
  notPurchased,
  networkError,
  serverError,
  failed,
}

/// The Microsoft Store, for the Store version of the Windows app: its
/// add-ons, buying one, and its rating dialog. The other side is
/// windows/runner/store_purchases.cpp.
class MsStoreService {
  MsStoreService._();

  static const MethodChannel _channel =
      MethodChannel('convert_the_spire/store');

  /// Whether this is the Store build on Windows. Run unpackaged (a
  /// developer's `flutter run`), [isAvailable] still says no.
  static bool get supported => !kIsWeb && Platform.isWindows && kMsStoreBuild;

  /// Whether the app runs from its Store package, where the Store answers.
  static Future<bool> isAvailable() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (e) {
      debugPrint('MsStoreService: isAvailable failed: $e');
      return false;
    }
  }

  /// The app's durable add-ons, with price and whether the user owns them.
  /// Empty when the Store cannot be reached.
  static Future<List<MsStoreAddOn>> addOns() async {
    if (!supported) return const [];
    try {
      final list = await _channel.invokeMethod<List<Object?>>('getAddOns');
      return [
        for (final value in list ?? const <Object?>[])
          if (MsStoreAddOn.fromMap(value) case final addOn?) addOn,
      ];
    } catch (e) {
      debugPrint('MsStoreService: getAddOns failed: $e');
      return const [];
    }
  }

  /// Shows the Store's purchase dialog for [storeId].
  static Future<MsStorePurchaseStatus> purchase(String storeId) async {
    if (!supported) return MsStorePurchaseStatus.failed;
    try {
      final answer = await _channel.invokeMethod<Map<Object?, Object?>>(
          'purchase', {'storeId': storeId});
      return parsePurchaseStatus(answer?['status']);
    } catch (e) {
      debugPrint('MsStoreService: purchase failed: $e');
      return MsStorePurchaseStatus.failed;
    }
  }

  @visibleForTesting
  static MsStorePurchaseStatus parsePurchaseStatus(Object? status) =>
      MsStorePurchaseStatus.values.firstWhere((s) => s.name == status,
          orElse: () => MsStorePurchaseStatus.failed);

  /// The Store's own rate-and-review dialog. False when it could not be
  /// shown (older Windows, no package): then [reviewPageUri] is the way.
  static Future<bool> requestRateAndReview() async {
    if (!supported) return false;
    try {
      final status = await _channel.invokeMethod<String>('rateAndReview');
      return status == 'succeeded' || status == 'canceled';
    } catch (e) {
      debugPrint('MsStoreService: rateAndReview failed: $e');
      return false;
    }
  }

  /// The app's review page in the Store app, or null outside the package.
  static Future<Uri?> reviewPageUri() async {
    if (!supported) return null;
    try {
      final family = await _channel.invokeMethod<String>('packageFamilyName');
      if (family == null || family.isEmpty) return null;
      return Uri.parse('ms-windows-store://review/?PFN=$family');
    } catch (e) {
      debugPrint('MsStoreService: packageFamilyName failed: $e');
      return null;
    }
  }
}
