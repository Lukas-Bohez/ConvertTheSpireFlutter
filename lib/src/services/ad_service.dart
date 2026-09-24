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
  static const String _debugNativeAdUnitId =
      'ca-app-pub-3940256099942544/2247696110';

  static const String _releaseBannerAdUnitId =
      'ca-app-pub-8418485814964449/4527775275';
  static const String _releaseInterstitialAdUnitId =
      'ca-app-pub-8418485814964449/3401876348';
  static const String _releaseRewardedAdUnitId =
      'ca-app-pub-8418485814964449/6938316192';
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
  Timer? _adBreakEndTimer;
  int _adsWatchedCount = 0;
  final AdFrequencyGate _adFrequencyGate = AdFrequencyGate();

  InterstitialAd? _preloadedInterstitial;
  bool _interstitialLoadInFlight = false;
  RewardedAd? _rewardedAd;

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
        _scheduleAdBreakEnd();
      }
    }
    _adsWatchedCount = prefs.getInt(_adsWatchedCountPrefsKey) ?? 0;
  }

  /// Arms a timer for the end of the current temporary ad break, so ads are
  /// loaded again as soon as it runs out. Nothing else reloads the
  /// interstitial while the app stays in the foreground, so without this the
  /// break would last until the next time the app is backgrounded.
  void _scheduleAdBreakEnd() {
    _adBreakEndTimer?.cancel();
    _adBreakEndTimer = null;
    final remaining = temporaryAdBreakRemaining;
    if (remaining == Duration.zero) return;
    // One extra second so hasTemporaryAdBreak is surely false when it fires.
    _adBreakEndTimer = Timer(
      remaining + const Duration(seconds: 1),
      _onAdBreakEnded,
    );
  }

  void _onAdBreakEnded() {
    _adBreakEndTimer = null;
    // The loaders re-check every gate (SDK initialised, ad-free purchase,
    // another break), so this is a no-op if ads must stay off.
    _preloadNextInterstitial();
    unawaited(loadRewarded());
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
    unawaited(banner.load());
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        banner.dispose();
        return null;
      },
    );
  }

  void _preloadNextInterstitial() {
    if (!_adsInitialised) return;
    if (!_isSupportedPlatform || _adsSuppressed) return;
    // One load at a time: the lifecycle observer, the dismiss callback and the
    // ad-break timer can all ask for a preload while one is still running.
    if (_preloadedInterstitial != null || _interstitialLoadInFlight) return;
    _interstitialLoadInFlight = true;

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoadInFlight = false;
          // Ads were switched off (purchase or ad break) while this loaded.
          if (_adsSuppressed) {
            ad.dispose();
            return;
          }
          // The next ad may already be preloaded while this one is on screen
          // (the app is paused then), so only clear the slot if it still
          // holds this ad.
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (identical(_preloadedInterstitial, ad)) {
                _preloadedInterstitial = null;
              }
              _preloadNextInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              if (identical(_preloadedInterstitial, ad)) {
                _preloadedInterstitial = null;
              }
              _preloadNextInterstitial();
            },
          );
          _preloadedInterstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _interstitialLoadInFlight = false;
          if (kDebugMode) debugPrint('Interstitial preload failed: $error');
          _preloadedInterstitial = null;
          Future.delayed(const Duration(minutes: 2), _preloadNextInterstitial);
        },
      ),
    ).catchError((Object error) {
      // The platform call itself failed, so neither callback will run.
      _interstitialLoadInFlight = false;
      if (kDebugMode) debugPrint('Interstitial preload threw: $error');
    });
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

  Future<NativeAd?> loadNativeAd({bool isDark = false}) async {
    // Same gate as every other format: no request before consent has been
    // checked and the SDK initialised.
    if (!_adsInitialised) return null;
    if (!_isSupportedPlatform || _adsSuppressed) return null;
    final completer = Completer<NativeAd?>();
    late final NativeAd nativeAd;

    final backgroundColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final primaryTextColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final tertiaryTextColor = isDark ? Colors.white54 : Colors.black45;

    nativeAd = NativeAd(
      adUnitId: nativeAdUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: backgroundColor,
        cornerRadius: 12,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: Colors.blue,
          size: 14,
          style: NativeTemplateFontStyle.bold,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: primaryTextColor,
          size: 14,
          style: NativeTemplateFontStyle.bold,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: secondaryTextColor,
          size: 12,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: tertiaryTextColor,
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
    unawaited(nativeAd.load());
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
    final ad = _preloadedInterstitial;
    if (ad == null) {
      // Nothing ready: start a load so the next opportunity has one.
      _preloadNextInterstitial();
      return;
    }
    if (!isInForeground) return;
    final last = _lastInterstitialShownAt;
    if (last != null &&
        DateTime.now().difference(last) < _fullScreenAdCooldown) {
      return;
    }
    if (!_adFrequencyGate.shouldShowAd()) return;
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

    // RewardedAd.show() completes as soon as the ad is on screen, before the
    // user has watched it and before onUserEarnedReward fires. Reading the
    // reward flag right after show() therefore always saw "not earned". Wait
    // for the ad to close (or fail to show) instead, then report the result.
    final closed = Completer<void>();
    Future<void>? rewardAction;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        unawaited(loadRewarded());
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        if (kDebugMode) debugPrint('Rewarded ad failed to show: $error');
        ad.dispose();
        unawaited(loadRewarded());
        if (!closed.isCompleted) closed.complete();
      },
    );
    try {
      await ad.show(
        onUserEarnedReward: (ad, reward) {
          // Start the reward right away (as before); it is awaited below.
          rewardAction ??= onRewardEarned();
        },
      );
    } catch (e) {
      // If showing the ad fails, attempt to reload for next time and return false.
      debugPrint('Rewarded ad show failed: $e');
      unawaited(loadRewarded());
      return false;
    }

    await closed.future;
    // Some mediation adapters report the reward just after the ad closes.
    if (rewardAction == null) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final action = rewardAction;
    if (action == null) return false;
    try {
      // Let the reward finish (for example the ad break being saved) before
      // the caller tells the user it was granted.
      await action;
    } catch (e) {
      debugPrint('Rewarded ad reward action failed: $e');
    }
    return true;
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
    _scheduleAdBreakEnd();
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

    debugPrint('AdService: initWithConsent() start');
    try {
      await _updateConsentInfo();
      await _showConsentFormIfRequired();
    } catch (e) {
      // Do not initialise ads just because the consent flow broke. Fall
      // through to canRequestAds(): it still reflects consent the user gave in
      // an earlier session, and stays false if they never gave any.
      debugPrint('AdService: consent flow error: $e');
    }

    final canRequest = await _canRequestAds();
    debugPrint('AdService: canRequestAds = $canRequest');
    if (!canRequest) {
      debugPrint('AdService: consent not obtained, ads not initialised');
      return;
    }

    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('AdService: MobileAds init failed, ads stay off: $e');
      return;
    }
    _adsInitialised = true;
    debugPrint('AdService: MobileAds initialised');
    _preloadNextInterstitial();
    unawaited(loadRewarded());
  }

  /// UMP's canRequestAds(), treating any error as "no consent".
  Future<bool> _canRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (e) {
      debugPrint('AdService: canRequestAds check failed: $e');
      return false;
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
    _preloadedInterstitial?.dispose();
    _preloadedInterstitial = null;
    _rewardedAd?.dispose();
    _rewardedAd = null;
  }
}
