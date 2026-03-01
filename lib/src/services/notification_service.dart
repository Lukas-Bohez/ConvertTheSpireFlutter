import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Cross-platform local notification helper.
///
/// All public methods silently no-op on unsupported platforms so callers
/// never need to worry about platform errors.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialised = false;
  int _nextNotificationId = 1;

  /// Whether the current platform has a notification implementation.
  static bool get _supported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  Future<void> initialize() async {
    if (!_supported || _initialised) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    try {
      await _plugin.initialize(settings: settings);
      _initialised = true;
    } catch (_) {
      // Platform not supported – silently disable notifications.
    }
  }

  /// Show a simple notification that a download finished.
  Future<void> showDownloadComplete(String title, String artist) async {
    if (!_initialised) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'download_channel',
        'Downloads',
        channelDescription: 'Download completion notifications',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    try {
      await _plugin.show(
        id: _nextNotificationId++,
        title: 'Download Complete',
        body: '$title \u2013 $artist',
        notificationDetails: details,
      );
    } catch (_) {
      // Notification failure must never affect downloads.
    }
  }

  /// Show ongoing progress notification (Android only).
  Future<void> showDownloadProgress(int id, String title, int progressPercent) async {
    if (!_initialised) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'download_progress',
        'Download Progress',
        channelDescription: 'Ongoing download progress',
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: 100,
        progress: progressPercent,
        ongoing: true,
      ),
    );

    try {
      await _plugin.show(id: id, title: 'Downloading', body: title, notificationDetails: details);
    } catch (_) {}
  }

  Future<void> cancel(int id) async {
    if (!_initialised) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }
}
