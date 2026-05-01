import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralizes the one-time Remove Ads unlock and its cached state.
class PurchaseService extends ChangeNotifier {
  PurchaseService._();

  static final PurchaseService instance = PurchaseService._();

  static const String removeAdsProductId = 'remove_ads';
  static const String _adFreePrefsKey = 'purchase_remove_ads_is_ad_free';

  bool _initialized = false;
  bool _storeAvailable = false;
  bool _isAdFree = false;
  ProductDetails? _removeAdsProduct;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  bool get storeAvailable => _storeAvailable;
  bool get isAdFree => _isAdFree;
  String get removeAdsPriceLabel => _removeAdsProduct?.price ?? 'Remove Ads';
  bool get canPurchaseRemoveAds => _storeAvailable && _removeAdsProduct != null;

  /// Loads cached ad-free state, restores prior purchases, and wires updates.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _isAdFree = prefs.getBool(_adFreePrefsKey) ?? false;

    _storeAvailable = await InAppPurchase.instance.isAvailable();
    if (_storeAvailable) {
      _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (error) {
          if (kDebugMode) debugPrint('Purchase stream error: $error');
        },
      );
      await _loadRemoveAdsProduct();
      unawaited(restorePurchases());
    }

    notifyListeners();
  }

  Future<void> _loadRemoveAdsProduct() async {
    if (!_storeAvailable) return;
    final response = await InAppPurchase.instance
        .queryProductDetails({removeAdsProductId});
    if (response.error != null && kDebugMode) {
      debugPrint('Product query error: ${response.error}');
    }
    _removeAdsProduct = response.productDetails.isEmpty
        ? null
        : response.productDetails.first;
    notifyListeners();
  }

  Future<void> purchaseRemoveAds() async {
    if (_isAdFree || !_storeAvailable) return;
    if (_removeAdsProduct == null) {
      await _loadRemoveAdsProduct();
    }
    final product = _removeAdsProduct;
    if (product == null) {
      if (kDebugMode) debugPrint('Remove Ads product is unavailable.');
      return;
    }

    await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  Future<void> restorePurchases() async {
    if (!_storeAvailable) return;
    await InAppPurchase.instance.restorePurchases();
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      if (purchase.productID == removeAdsProductId &&
          (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored)) {
        await _setAdFree(true);
      }

      if (purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  Future<void> _setAdFree(bool value) async {
    if (_isAdFree == value) return;
    _isAdFree = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adFreePrefsKey, value);
    notifyListeners();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
