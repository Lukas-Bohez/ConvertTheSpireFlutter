import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      final prefs = await SharedPreferences.getInstance();

      if (prefs.getBool(_reviewDoneKey) ?? false) return;

      final launchCount = prefs.getInt(_launchCountKey) ?? 0;
      final lastPrompt = prefs.getInt(_lastReviewKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final daysSinceLastPrompt = (now - lastPrompt) / (1000 * 60 * 60 * 24);

      if (launchCount < 5) return;
      if (lastPrompt > 0 && daysSinceLastPrompt < 14) return;

      final isAvailable = await _inAppReview.isAvailable();
      if (!isAvailable) return;

      await prefs.setInt(_lastReviewKey, now);
      await prefs.setBool(_reviewDoneKey, true);
      await _inAppReview.requestReview();
    } catch (_) {}
  }

  /// Fallback: open store listing directly (use for manual "Rate this app" button)
  static Future<void> openStoreListing() async {
    try {
      await _inAppReview.openStoreListing(appStoreId: 'com.torrentspire.ai');
    } catch (_) {}
  }
}
