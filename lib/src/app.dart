import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'screens/home_screen.dart';
import 'services/convert_service.dart';
import 'services/download_service.dart';
import 'services/ffmpeg_service.dart';
import 'services/installer_service.dart';
import 'services/log_service.dart';
import 'services/settings_store.dart';
import 'services/youtube_service.dart';
import 'state/app_controller.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppController? _controller;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    final logs = LogService();
    final settingsStore = SettingsStore();
    final youtube = YouTubeService();
    final ytExplode = YoutubeExplode();
    final ffmpeg = FfmpegService();
    final downloadService = DownloadService(yt: ytExplode, ffmpeg: ffmpeg);
    final convertService = ConvertService(ffmpeg: ffmpeg);
    final installerService = InstallerService();

    final controller = AppController(
      settingsStore: settingsStore,
      youtube: youtube,
      downloadService: downloadService,
      convertService: convertService,
      installerService: installerService,
      logs: logs,
    );
    await controller.init();
    if (mounted) {
      setState(() {
        _controller = controller;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Convert the Spire',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: _controller == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : HomeScreen(controller: _controller!),
    );
  }
}
