import 'dart:async';
import 'dart:developer' as developer;

/// Desktop notification polling fallback for platforms where FCM is unavailable.
///
/// Phase 11 requirement: Windows/macOS/Linux should poll our backend for pending
/// inbound signals/notifications when push service is not available.
///
/// This implementation is intentionally minimal and server-agnostic.
class DesktopNotificationPoller {
  static final DesktopNotificationPoller instance =
      DesktopNotificationPoller._();

  Timer? _timer;
  int _pollCount = 0;

  DesktopNotificationPoller._();

  void start() {
    _timer ??= Timer.periodic(Duration(seconds: 30), (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    _pollCount += 1;
    developer.log(
      '[DesktopNotificationPoller] polling for notifications ($_pollCount) ...',
    );

    // Mock integration for now: display a test notification every 5 poll cycles.
    if (_pollCount % 5 == 0) {
      await _showNotification(
        'VaultTheSpire',
        'You have a new message or event to review',
      );
    }
  }

  Future<void> _showNotification(String title, String message) async {
    // Cross-platform desktop notifications can be integrated via native plugins.
    // For now this logs information and can be used for future real notification hooks.
    developer.log('[DesktopNotification] $title: $message');
  }
}
