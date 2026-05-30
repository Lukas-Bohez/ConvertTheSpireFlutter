import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_flags.dart';
import 'purchase_service.dart';

class AdFrequencyGate {
  static const int minInteractionsBetweenAds = 2;
  static const Duration sessionGracePeriod = Duration(minutes: 1);
  static const Duration minTimeBetweenAds = Duration(minutes: 1);

  final DateTime _sessionStartedAt = DateTime.now();
  int _interactionsSinceLast = 0;
  DateTime _lastAdShown = DateTime.fromMillisecondsSinceEpoch(0);

  bool shouldShowAd() {
    if (AdService.instance.adsRemoved) return false;
    if (DateTime.now().difference(_sessionStartedAt) < sessionGracePeriod) {
      return false;
    }
    if (_interactionsSinceLast < minInteractionsBetweenAds) return false;
    if (DateTime.now().difference(_lastAdShown) < minTimeBetweenAds) {
      return false;
    }
    return true;
  }

  void registerInteraction() {
    _interactionsSinceLast++;
  }

  void recordAdShown() {
    _interactionsSinceLast = 0;
    _lastAdShown = DateTime.now();
  }
}

/// Coordinates Google Mobile Ads loading, display throttling, and reward logic.
class AdService with WidgetsBindingObserver {
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
  static const String _releaseNativeAdUnitId =
      'ca-app-pub-8418485814964449/7181339255';

  static const Duration _fullScreenAdCooldown = Duration(minutes: 1);
  static const String _temporaryAdBreakPrefsKey =
      'monetization_temporary_ad_break_until_ms';
  static const String _adsWatchedCountPrefsKey =
      'monetization_ads_watched_count';

  bool _initialized = false;
  bool _isSupportedPlatform = false;
  bool _isInForeground = true;
  bool _adsInitialised = false;
  DateTime? _lastInterstitialShownAt;
  DateTime? _temporaryAdBreakUntil;
  int _adsWatchedCount = 0;
  final AdFrequencyGate _adFrequencyGate = AdFrequencyGate();

  InterstitialAd? _interstitialAd;
  InterstitialAd? _preloadedInterstitial;
  RewardedAd? _rewardedAd;
  RewardedInterstitialAd? _rewardedInterstitialAd;

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

  bool get isInForeground => _isInForeground;
  bool get adsAvailable => _isSupportedPlatform && !_adsSuppressed;
  bool get adsRemoved => PurchaseService.instance.isAdFree;

  String get bannerAdUnitId =>
      kDebugMode ? _debugBannerAdUnitId : _releaseBannerAdUnitId;
  String get interstitialAdUnitId =>
      kDebugMode ? _debugInterstitialAdUnitId : _releaseInterstitialAdUnitId;
  String get rewardedAdUnitId =>
      kDebugMode ? _debugRewardedAdUnitId : _releaseRewardedAdUnitId;
  String get rewardedInterstitialAdUnitId => kDebugMode
      ? _debugRewardedInterstitialAdUnitId
      : _releaseRewardedInterstitialAdUnitId;
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
    WidgetsBinding.instance.addObserver(this);
    await _loadPersistedAdState();
    if (!_isSupportedPlatform) return;
    // Ads will be preloaded after UMP consent check completes in main.dart
    // via initAdsWithConsent(). Do NOT preload ads here — wait for consent.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInForeground = state == AppLifecycleState.resumed;
    if (!_isInForeground) _preloadNextInterstitial();
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
    if (!_adsInitialised) return null;
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
    if (!_adsInitialised) return null;
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

  void _preloadNextInterstitial() {
    if (!_adsInitialised) return;
    if (!_isSupportedPlatform || _adsSuppressed) return;
    if (_preloadedInterstitial != null) return;

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _preloadedInterstitial = null;
              _preloadNextInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _preloadedInterstitial = null;
              _preloadNextInterstitial();
            },
          );
          _preloadedInterstitial = ad;
        },
        onAdFailedToLoad: (error) {
          if (kDebugMode) debugPrint('Interstitial preload failed: $error');
          _preloadedInterstitial = null;
          Future.delayed(const Duration(minutes: 2), _preloadNextInterstitial);
        },
      ),
    );
  }

  Future<RewardedAd?> loadRewarded() async {
    if (!_adsInitialised) return null;
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
    if (!_adsInitialised) return null;
    if (!_isSupportedPlatform || _adsSuppressed) return null;
    if (_rewardedInterstitialAd != null) return _rewardedInterstitialAd;
    final completer = Completer<RewardedInterstitialAd?>();
    await RewardedInterstitialAd.load(
      adUnitId: rewardedInterstitialAdUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
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
    if (!isInForeground) return;
    final last = _lastInterstitialShownAt;
    if (last != null &&
        DateTime.now().difference(last) < _fullScreenAdCooldown) {
      return;
    }
    if (!_adFrequencyGate.shouldShowAd()) return;
    final ad = _preloadedInterstitial;
    if (ad == null) return;
    _preloadedInterstitial = null;
    _lastInterstitialShownAt = DateTime.now();
    _adFrequencyGate.recordAdShown();
    await ad.show();
  }

  void registerInteraction() {
    _adFrequencyGate.registerInteraction();
  }

  Future<bool> _showRewardedAdWithRewardAction(
    Future<void> Function() onRewardEarned,
  ) async {
    if (!_isSupportedPlatform || _adsSuppressed) return false;
    // Try to load rewarded ad and wait briefly for the SDK callback to complete.
    await loadRewarded();
    RewardedAd? ad = _rewardedAd;
    // Wait a short period for the ad object to be assigned by the loader
    var attempts = 0;
    while (ad == null && attempts < 8) {
      await Future.delayed(const Duration(milliseconds: 500));
      ad = _rewardedAd;
      attempts++;
    }
    if (ad == null) return false;

    _rewardedAd = null;
    var rewardEarned = false;
    try {
      await ad.show(
        onUserEarnedReward: (ad, reward) {
          rewardEarned = true;
          unawaited(onRewardEarned());
        },
      );
    } catch (e) {
      // If showing the ad fails, attempt to reload for next time and return false.
      debugPrint('Rewarded ad show failed: $e');
      unawaited(loadRewarded());
      return false;
    }
    return rewardEarned;
  }

  Future<void> _incrementAdsWatchedCount() async {
    _adsWatchedCount += 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_adsWatchedCountPrefsKey, _adsWatchedCount);
  }

  Future<void> _grantTemporaryAdBreak(Duration duration) async {
    final until = DateTime.now().add(duration);
    if (_temporaryAdBreakUntil != null &&
        _temporaryAdBreakUntil!.isAfter(until)) {
      return;
    }
    _temporaryAdBreakUntil = until;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_temporaryAdBreakPrefsKey, until.millisecondsSinceEpoch);
    disposeAllAds();
  }

  /// Call this once at app startup, before any ad is loaded.
  /// Handles UMP consent for EU/EEA users and initialises the SDK for everyone.
  /// Must be called in main.dart AFTER AdService.instance.initialize().
  ///
  /// IMPORTANT: Before UMP will display a consent form, you must create a GDPR
  /// message in your AdMob account:
  ///   AdMob dashboard → Privacy & messaging → GDPR → Create message
  ///   Set targeting to: "Countries subject to GDPR (EEA and UK)"
  ///   Enable "Consent" and "Manage options" (do NOT enable "Close (do not consent)")
  ///   Publish the message.
  /// Without this step, requestConsentInfoUpdate() will always return NOT_REQUIRED
  /// and no form will ever show, even for EU users.
  Future<void> initWithConsent() async {
    if (!_isSupportedPlatform) return;

    try {
      debugPrint('AdService: initWithConsent() start');
      await _updateConsentInfo();
      await _showConsentFormIfRequired();

      final canRequest = await ConsentInformation.instance.canRequestAds();
      debugPrint('AdService: canRequestAds = $canRequest');

      if (canRequest) {
        await MobileAds.instance.initialize();
        _adsInitialised = true;
        debugPrint('AdService: MobileAds initialised');
        _preloadNextInterstitial();
        unawaited(loadRewarded());
        unawaited(loadRewardedInterstitial());
      } else {
        debugPrint('AdService: consent not obtained, ads not initialised');
      }
    } catch (e) {
      debugPrint('AdService: consent flow error, attempting fallback init: $e');
      try {
        await MobileAds.instance.initialize();
        _adsInitialised = true;
        _preloadNextInterstitial();
        unawaited(loadRewarded());
        unawaited(loadRewardedInterstitial());
      } catch (e2) {
        debugPrint('AdService: fallback init also failed: $e2');
      }
    }
  }

  Future<void> initAdsWithConsent() => initWithConsent();

  /// Request consent info update from UMP SDK.
  /// Handles errors gracefully by completing the future so the flow continues.
  Future<void> _updateConsentInfo() async {
    final params = ConsentRequestParameters();
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () {
        unawaited(() async {
          final status = await ConsentInformation.instance.getConsentStatus();
          debugPrint('AdService: consent status after update = $status');
        }());
        debugPrint('AdService: consent info updated successfully');
        if (!completer.isCompleted) completer.complete();
      },
      (error) {
        debugPrint('AdService: consent info update failed: ${error.message}');
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('AdService: consent info update timed out');
      },
    );
  }

  Future<void> _showConsentFormIfRequired() async {
    final completer = Completer<void>();
    await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
      if (formError != null) {
        debugPrint('AdService: consent form error: ${formError.message}');
      }
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        debugPrint('AdService: consent form timed out');
      },
    );
  }

  // TO TEST UMP LOCALLY (debug builds only — never in release):
  // 1. Run the app once and find your test device hash in logcat:
  //    Search for: "Use ConsentDebugSettings.testIdentifiers"
  // 2. Force EEA geography to simulate an EU user:
  //
  // final debugSettings = ConsentDebugSettings(
  //   debugGeography: DebugGeography.debugGeographyEea,
  //   testIdentifiers: ["YOUR-HASHED-TEST-DEVICE-ID"],
  // );
  // final params = ConsentRequestParameters(consentDebugSettings: debugSettings);
  //
  // 3. To reset consent state and simulate a first-time user:
  //    ConsentInformation.instance.reset(); // debug only — never ship this

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

  /// Shows a rewarded ad and runs a custom reward action when the user
  /// earns the reward. Returns true when reward was granted.
  Future<bool> showRewardedWithCustomReward(
      Future<void> Function() onRewardEarned) async {
    return _showRewardedAdWithRewardAction(onRewardEarned);
  }

  /// Disposes any preloaded ad instances to free SDK resources.
  void disposeAllAds() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
    _preloadedInterstitial?.dispose();
    _preloadedInterstitial = null;
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _rewardedInterstitialAd?.dispose();
    _rewardedInterstitialAd = null;
  }
}
