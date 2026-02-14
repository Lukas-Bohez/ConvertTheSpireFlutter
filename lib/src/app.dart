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
  YoutubeExplode? _ytExplode;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void dispose() {
    _ytExplode?.close();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initController() async {
    try {
      final logs = LogService();
      final settingsStore = SettingsStore();
      final ytExplode = YoutubeExplode();
      _ytExplode = ytExplode;
      final youtube = YouTubeService(yt: ytExplode);
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = '$e';
        });
      }
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
      home: _initError != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Failed to start', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(_initError!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() { _initError = null; });
                          _initController();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : _controller == null
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : HomeScreen(controller: _controller!),
    );
  }
}
