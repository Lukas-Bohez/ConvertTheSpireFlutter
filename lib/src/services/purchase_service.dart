import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_flags.dart';
import '../features/colour_rewards/colour_reward_service.dart';

/// Centralizes the one-time Remove Ads unlock and its cached state.
class PurchaseService extends ChangeNotifier {
  PurchaseService._();

  static final PurchaseService instance = PurchaseService._();

  static const String removeAdsProductId = 'remove_ads';
  static const String getAllThemesProductId = 'get_all_themes';
  static const String _adFreePrefsKey = 'purchase_remove_ads_is_ad_free';
  static const String _allThemesPrefsKey = 'colour_all_purchased';

  bool _initialized = false;
  bool _storeAvailable = false;
  bool _isAdFree = false;
  bool _hasAllThemes = false;
  ProductDetails? _removeAdsProduct;
  ProductDetails? _getAllThemesProduct;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  bool get storeAvailable => _storeAvailable;
  bool get isAdFree => _isAdFree;
  bool get hasAllThemes => _hasAllThemes;
  String get removeAdsPriceLabel => _removeAdsProduct?.price ?? 'Remove Ads';
  String get getAllThemesPriceLabel =>
      _getAllThemesProduct?.price ?? 'Unlock All 28 Colours';
  bool get canPurchaseRemoveAds => _storeAvailable && _removeAdsProduct != null;
  bool get canPurchaseAllThemes =>
      _storeAvailable && _getAllThemesProduct != null && !_hasAllThemes;

  /// Loads cached ad-free state, restores prior purchases, and wires updates.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _isAdFree = prefs.getBool(_adFreePrefsKey) ?? false;
    _hasAllThemes = prefs.getBool(_allThemesPrefsKey) ?? false;

    // On GitHub release / non-Play builds we consider all colours unlocked
    // by default so users don't need to purchase or watch ads to collect them.
    if (kIsGithubRelease) {
      _hasAllThemes = true;
      await prefs.setBool(_allThemesPrefsKey, true);
      await ColourRewardService.instance.unlockAllColours();
    }

    _storeAvailable = await InAppPurchase.instance.isAvailable();
    if (_storeAvailable) {
      _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (error) {
          if (kDebugMode) debugPrint('Purchase stream error: $error');
        },
      );
      await _loadProducts();
      unawaited(restorePurchases());
    }

    if (_hasAllThemes) {
      await ColourRewardService.instance.unlockAllColours();
    }

    notifyListeners();
  }

  Future<void> _loadProducts() async {
    if (!_storeAvailable) return;
    final response = await InAppPurchase.instance.queryProductDetails({
      removeAdsProductId,
      getAllThemesProductId,
    });
    if (response.error != null && kDebugMode) {
      debugPrint('Product query error: ${response.error}');
    }
    _removeAdsProduct = response.productDetails
        .where((product) => product.id == removeAdsProductId)
        .cast<ProductDetails?>()
        .firstWhere((product) => product != null, orElse: () => null);
    _getAllThemesProduct = response.productDetails
        .where((product) => product.id == getAllThemesProductId)
        .cast<ProductDetails?>()
        .firstWhere((product) => product != null, orElse: () => null);
    notifyListeners();
  }

  Future<void> purchaseRemoveAds() async {
    if (_isAdFree || !_storeAvailable) return;
    if (_removeAdsProduct == null) {
      await _loadProducts();
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

  Future<void> purchaseAllThemes() async {
    if (_hasAllThemes || !_storeAvailable) return;
    if (_getAllThemesProduct == null) {
      await _loadProducts();
    }
    final product = _getAllThemesProduct;
    if (product == null) {
      if (kDebugMode) debugPrint('Get All Themes product is unavailable.');
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

      if (purchase.productID == getAllThemesProductId &&
          (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored)) {
        await _setAllThemes(true);
        await ColourRewardService.instance.unlockAllColours();
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

  Future<void> _setAllThemes(bool value) async {
    if (_hasAllThemes == value) return;
    _hasAllThemes = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_allThemesPrefsKey, value);
    notifyListeners();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
