import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_flags.dart';
import 'purchase_service.dart';

/// Coordinates Google Mobile Ads loading, display throttling, and reward logic.
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  static const String _debugBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _debugInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _debugRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _debugRewardedInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/5354046379';
  static const String _debugAppOpenAdUnitId =
      'ca-app-pub-3940256099942544/3419835294';
  static const String _debugNativeAdUnitId =
      'ca-app-pub-3940256099942544/2247696110';

  static const String _releaseBannerAdUnitId =
      'ca-app-pub-8418485814964449/4527775275';
  static const String _releaseInterstitialAdUnitId =
      'ca-app-pub-8418485814964449/3401876348';
  static const String _releaseRewardedAdUnitId =
      'ca-app-pub-8418485814964449/6938316192';
  static const String _releaseRewardedInterstitialAdUnitId =
      'ca-app-pub-8418485814964449/7832075944';
  static const String _releaseAppOpenAdUnitId =
      'ca-app-pub-8418485814964449/1961547024';
  static const String _releaseNativeAdUnitId =
      'ca-app-pub-8418485814964449/7181339255';

  static const Duration _fullScreenAdCooldown = Duration(minutes: 3);
  static const String _temporaryAdBreakPrefsKey =
      'monetization_temporary_ad_break_until_ms';
  static const String _adsWatchedCountPrefsKey =
      'monetization_ads_watched_count';

  bool _initialized = false;
  bool _isSupportedPlatform = false;
  DateTime? _lastInterstitialShownAt;
  DateTime? _lastAppOpenShownAt;
  DateTime? _temporaryAdBreakUntil;
  int _adsWatchedCount = 0;

  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  RewardedInterstitialAd? _rewardedInterstitialAd;
  AppOpenAd? _appOpenAd;

  bool get hasTemporaryAdBreak =>
      _temporaryAdBreakUntil != null &&
      DateTime.now().isBefore(_temporaryAdBreakUntil!);
  int get adsWatchedCount => _adsWatchedCount;
  Duration get temporaryAdBreakRemaining {
    final until = _temporaryAdBreakUntil;
    if (until == null) return Duration.zero;
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
  bool get adsAvailable => _isSupportedPlatform && !_adsSuppressed;

  String get bannerAdUnitId =>
      kDebugMode ? _debugBannerAdUnitId : _releaseBannerAdUnitId;
  String get interstitialAdUnitId =>
      kDebugMode ? _debugInterstitialAdUnitId : _releaseInterstitialAdUnitId;
  String get rewardedAdUnitId =>
      kDebugMode ? _debugRewardedAdUnitId : _releaseRewardedAdUnitId;
  String get rewardedInterstitialAdUnitId => kDebugMode
      ? _debugRewardedInterstitialAdUnitId
      : _releaseRewardedInterstitialAdUnitId;
  String get appOpenAdUnitId =>
      kDebugMode ? _debugAppOpenAdUnitId : _releaseAppOpenAdUnitId;
  String get nativeAdUnitId =>
      kDebugMode ? _debugNativeAdUnitId : _releaseNativeAdUnitId;

    bool get _adsDisabled => PurchaseService.instance.isAdFree;
    bool get _adsSuppressed => _adsDisabled || hasTemporaryAdBreak;
  bool get _supportsPlatform =>
      kPlayStoreBuild && !kIsWeb && Platform.isAndroid;

  /// Loads cached monetization state and preloads the full-screen ads.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _isSupportedPlatform = _supportsPlatform;
    await _loadPersistedAdState();
    if (!_isSupportedPlatform || _adsSuppressed) return;
    unawaited(loadAppOpen());
    unawaited(loadInterstitial());
    unawaited(loadRewarded());
    unawaited(loadRewardedInterstitial());
  }

  Future<void> _loadPersistedAdState() async {
    final prefs = await SharedPreferences.getInstance();
    final adBreakUntilMs = prefs.getInt(_temporaryAdBreakPrefsKey);
    if (adBreakUntilMs != null) {
      final until = DateTime.fromMillisecondsSinceEpoch(adBreakUntilMs);
      if (DateTime.now().isBefore(until)) {
        _temporaryAdBreakUntil = until;
      }
    }
    _adsWatchedCount = prefs.getInt(_adsWatchedCountPrefsKey) ?? 0;
  }

  Future<BannerAd?> loadBanner() async {
    if (!_isSupportedPlatform || _adsSuppressed) return null;
    final completer = Completer<BannerAd?>();
    late final BannerAd banner;
    banner = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!completer.isCompleted) completer.complete(banner);
        },
        onAdFailedToLoad: (ad, error) {
          if (kDebugMode) debugPrint('Banner failed to load: $error');
          ad.dispose();
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );
    banner.load();
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        banner.dispose();
        return null;
      },
    );
  }

  Future<InterstitialAd?> loadInterstitial() async {
    if (!_isSupportedPlatform || _adsSuppressed) return null;
    if (_interstitialAd != null) return _interstitialAd;
    final completer = Completer<InterstitialAd?>();
    await InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              unawaited(loadInterstitial());
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              unawaited(loadInterstitial());
            },
          );
          _interstitialAd = ad;
          if (!completer.isCompleted) completer.complete(ad);
        },
        onAdFailedToLoad: (error) {
          if (kDebugMode) debugPrint('Interstitial failed to load: $error');
          _interstitialAd = null;
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  Future<RewardedAd?> loadRewarded() async {
    if (!_isSupportedPlatform || _adsSuppressed) return null;
    if (_rewardedAd != null) return _rewardedAd;
    final completer = Completer<RewardedAd?>();
    await RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedAd = null;
              unawaited(loadRewarded());
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _rewardedAd = null;
              unawaited(loadRewarded());
            },
          );
          _rewardedAd = ad;
          if (!completer.isCompleted) completer.complete(ad);
        },
        onAdFailedToLoad: (error) {
          if (kDebugMode) debugPrint('Rewarded failed to load: $error');
          _rewardedAd = null;
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  Future<RewardedInterstitialAd?> loadRewardedInterstitial() async {
    if (!_isSupportedPlatform || _adsSuppressed) return null;
    if (_rewardedInterstitialAd != null) return _rewardedInterstitialAd;
    final completer = Completer<RewardedInterstitialAd?>();
    await RewardedInterstitialAd.load(
      adUnitId: rewardedInterstitialAdUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback:
          RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedInterstitialAd = null;
              unawaited(loadRewardedInterstitial());
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _rewardedInterstitialAd = null;
              unawaited(loadRewardedInterstitial());
            },
          );
          _rewardedInterstitialAd = ad;
          if (!completer.isCompleted) completer.complete(ad);
        },
        onAdFailedToLoad: (error) {
          if (kDebugMode) {
            debugPrint('Rewarded interstitial failed to load: $error');
          }
          _rewardedInterstitialAd = null;
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  Future<AppOpenAd?> loadAppOpen() async {
    if (!_isSupportedPlatform || _adsSuppressed) return null;
    if (_appOpenAd != null) return _appOpenAd;
    final completer = Completer<AppOpenAd?>();
    await AppOpenAd.load(
      adUnitId: appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _appOpenAd = null;
              unawaited(loadAppOpen());
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _appOpenAd = null;
              unawaited(loadAppOpen());
            },
          );
          _appOpenAd = ad;
          if (!completer.isCompleted) completer.complete(ad);
        },
        onAdFailedToLoad: (error) {
          if (kDebugMode) debugPrint('App open failed to load: $error');
          _appOpenAd = null;
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  Future<NativeAd?> loadNativeAd() async {
    if (!_isSupportedPlatform || _adsSuppressed) return null;
    final completer = Completer<NativeAd?>();
    late final NativeAd nativeAd;
    nativeAd = NativeAd(
      adUnitId: nativeAdUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: Colors.white,
        cornerRadius: 12,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: Colors.blue,
          size: 14,
          style: NativeTemplateFontStyle.bold,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.black87,
          size: 14,
          style: NativeTemplateFontStyle.bold,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.black54,
          size: 12,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.black45,
          size: 11,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!completer.isCompleted) completer.complete(nativeAd);
        },
        onAdFailedToLoad: (ad, error) {
          if (kDebugMode) debugPrint('Native ad failed to load: $error');
          ad.dispose();
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );
    nativeAd.load();
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        nativeAd.dispose();
        return null;
      },
    );
  }

  /// Shows an interstitial after a successful download, respecting cooldowns.
  Future<void> maybeShowInterstitialAfterSuccess() async {
    if (!_isSupportedPlatform || _adsSuppressed) return;
    final last = _lastInterstitialShownAt;
    if (last != null && DateTime.now().difference(last) < _fullScreenAdCooldown) {
      return;
    }
    await loadInterstitial();
    final ad = _interstitialAd;
    if (ad == null) return;
    _interstitialAd = null;
    _lastInterstitialShownAt = DateTime.now();
    await ad.show();
  }

  /// Shows the app-open ad when the app is launched or foregrounded.
  Future<void> showAppOpenAdIfAvailable() async {
    if (!_isSupportedPlatform || _adsSuppressed) return;
    final last = _lastAppOpenShownAt;
    if (last != null && DateTime.now().difference(last) < _fullScreenAdCooldown) {
      return;
    }
    await loadAppOpen();
    final ad = _appOpenAd;
    if (ad == null) return;
    _appOpenAd = null;
    _lastAppOpenShownAt = DateTime.now();
    await ad.show();
  }

  /// Handles lifecycle events from the app shell.
  void handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(showAppOpenAdIfAvailable());
    }
  }

  Future<bool> _showRewardedAdWithRewardAction(
    Future<void> Function() onRewardEarned,
  ) async {
    if (!_isSupportedPlatform || _adsSuppressed) return false;
    await loadRewarded();
    final ad = _rewardedAd;
    if (ad == null) return false;

    _rewardedAd = null;
    var rewardEarned = false;
    await ad.show(
      onUserEarnedReward: (ad, reward) {
        rewardEarned = true;
        unawaited(onRewardEarned());
      },
    );
    return rewardEarned;
  }

  Future<void> _incrementAdsWatchedCount() async {
    _adsWatchedCount += 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_adsWatchedCountPrefsKey, _adsWatchedCount);
  }

  Future<void> _grantTemporaryAdBreak(Duration duration) async {
    final until = DateTime.now().add(duration);
    if (_temporaryAdBreakUntil != null && _temporaryAdBreakUntil!.isAfter(until)) {
      return;
    }
    _temporaryAdBreakUntil = until;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_temporaryAdBreakPrefsKey, until.millisecondsSinceEpoch);
    disposeAllAds();
  }

  /// Shows a rewarded ad and pauses ad delivery for 30 minutes as goodwill.
  Future<bool> showRewardedAdForTemporaryAdBreak({
    Duration duration = const Duration(minutes: 30),
  }) async {
    return _showRewardedAdWithRewardAction(() async {
      await _incrementAdsWatchedCount();
      await _grantTemporaryAdBreak(duration);
    });
  }

  /// Shows a rewarded ad as a goodwill support action without pausing ads.
  Future<bool> showRewardedAdToSupportProject() async {
    return _showRewardedAdWithRewardAction(() async {
      await _incrementAdsWatchedCount();
    });
  }

  /// Disposes any preloaded ad instances to free SDK resources.
  void disposeAllAds() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _rewardedInterstitialAd?.dispose();
    _rewardedInterstitialAd = null;
    _appOpenAd?.dispose();
    _appOpenAd = null;
  }
}
