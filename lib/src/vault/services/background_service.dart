import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_engine_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: false,
      isForegroundMode: false,
      notificationChannelId: 'torrent_engine_channel',
      initialNotificationTitle: 'Vault The Spire Torrent Service',
      initialNotificationContent: 'Initializing torrent background service...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onServiceStart,
      onBackground: onIosBackground,
    ),
  );

  if (!(await service.isRunning())) {
    await service.startService();
  }
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  return true;
}

@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    if (await service.isForegroundService()) {
      await service.setAsForegroundService();
      await service.setForegroundNotificationInfo(
        title: 'Vault The Spire Torrent Service',
        content: 'Service is running',
      );
    }
  }

  // Setup listeners from notification actions.
  service.on('pause').listen((event) async {
    TorrentEngineService.instance.pauseAll();
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        await service.setForegroundNotificationInfo(
          title: 'Torrent paused',
          content: 'All downloads paused from notification',
        );
      }
    }
  });

  service.on('resume').listen((event) async {
    TorrentEngineService.instance.resumeAll();
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        await service.setForegroundNotificationInfo(
          title: 'Torrent resuming',
          content: 'All downloads resumed from notification',
        );
      }
    }
  });

  service.on('stop_service').listen((event) {
    service.invoke('update');
    service.stopSelf();
  });

  // Periodically update notification based on current engine stats.
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    if (!await FlutterBackgroundService().isRunning()) {
      timer.cancel();
      return;
    }
    final status = TorrentEngineService.instance.aggregateStatus();
    final speedMBs = (status.downloadSpeed / 1024 / 1024).toStringAsFixed(2);
    final progressPct = (status.progress * 100).toStringAsFixed(1);

    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        await service.setForegroundNotificationInfo(
          title: '⚡ $speedMBs MB/s - $progressPct%',
          content: 'DHT ${status.dhtNodes}, Peers ${status.peers}',
        );
      }
    }

    if (TorrentEngineService.instance.shouldStopService()) {
      service.stopSelf();
      timer.cancel();
    }
  });

  // Background event to handle status update from UI thread.
  service.on('update_status').listen((event) async {
    final double speed = (event?['downloadSpeed'] as num?)?.toDouble() ?? 0.0;
    final double progress = (event?['progress'] as num?)?.toDouble() ?? 0.0;
    final int peers = (event?['peers'] as num?)?.toInt() ?? 0;
    final int dht = (event?['dhtNodes'] as num?)?.toInt() ?? 0;

    final speedMBs = (speed / 1024 / 1024).toStringAsFixed(2);
    final progressPct = (progress * 100).toStringAsFixed(1);

    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        await service.setForegroundNotificationInfo(
          title: '⚡ $speedMBs MB/s - $progressPct%',
          content: 'DHT $dht • Peers $peers',
        );
      }
    }
  });
}
