import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ms_store_service.dart';

class ReviewService {
  static const _launchCountKey = 'launch_count';
  static const _lastReviewKey = 'last_review_prompt';
  static const _reviewDoneKey = 'review_done';

  static final _inAppReview = InAppReview.instance;

  /// Call this on every app launch from main()
  static Future<void> trackLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(_launchCountKey) ?? 0) + 1;
      await prefs.setInt(_launchCountKey, count);
    } catch (_) {}
  }

  /// Call this after a positive user action.
  static Future<void> maybePromptReview() async {
    try {
      if (kIsWeb) return;
      final platform = defaultTargetPlatform;
      final msStore = MsStoreService.supported;
      if (platform != TargetPlatform.android &&
          platform != TargetPlatform.iOS &&
          !msStore) {
        return;
      }

      const isPlayBuild =
          bool.fromEnvironment('PLAY_STORE_BUILD', defaultValue: false);
      if (platform == TargetPlatform.android && !isPlayBuild) return;

      final prefs = await SharedPreferences.getInstance();

      if (prefs.getBool(_reviewDoneKey) ?? false) return;

      final launchCount = prefs.getInt(_launchCountKey) ?? 0;
      final lastPrompt = prefs.getInt(_lastReviewKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final daysSinceLastPrompt = (now - lastPrompt) / (1000 * 60 * 60 * 24);

      if (launchCount < 5) return;
      if (lastPrompt > 0 && daysSinceLastPrompt < 14) return;

      if (msStore) {
        if (!await MsStoreService.isAvailable()) return;
        await prefs.setInt(_lastReviewKey, now);
        await prefs.setBool(_reviewDoneKey, true);
        await MsStoreService.requestRateAndReview();
        return;
      }

      final isAvailable = await _inAppReview.isAvailable();
      if (!isAvailable) return;

      await prefs.setInt(_lastReviewKey, now);
      await prefs.setBool(_reviewDoneKey, true);
      await _inAppReview.requestReview();
    } catch (_) {}
  }

  static final Uri _projectPage =
      Uri.parse('https://github.com/Lukas-Bohez/ConvertTheSpireFlutter');

  /// Opens where people can rate the app, for the "Rate" buttons: the Play
  /// Store listing on Android, the Microsoft Store's rating dialog in the
  /// Store build on Windows, the project's GitHub page elsewhere.
  static Future<void> openStoreListing() async {
    if (MsStoreService.supported) {
      if (await MsStoreService.requestRateAndReview()) return;
      final page = await MsStoreService.reviewPageUri();
      if (page != null) {
        try {
          if (await launchUrl(page)) return;
        } catch (_) {
          // Fall through to the project page.
        }
      }
    }
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _inAppReview.openStoreListing(appStoreId: 'com.torrentspire.ai');
        return;
      } catch (_) {
        // Fall through to the project page.
      }
    }
    try {
      await launchUrl(_projectPage, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
