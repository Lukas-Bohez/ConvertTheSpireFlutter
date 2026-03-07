import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'dlna_control_service.dart';
import 'dlna_discovery_service.dart';
import 'local_media_server.dart';

/// Stream states for the screencast session.
enum ScreencastState { idle, starting, streaming, stopping, error }

/// Captures the desktop screen + audio via FFmpeg and streams it over HTTP
/// so DLNA/Chromecast renderers on the LAN can play it.
///
/// Desktop-only (Windows / Linux).  On Android the platform lacks a
/// command-line FFmpeg with screen-capture capabilities.
class ScreencastService {
  final DlnaDiscoveryService _discovery = DlnaDiscoveryService();
  final DlnaControlService _control = DlnaControlService();

  Process? _ffmpeg;
  HttpServer? _httpServer;
  ScreencastState _state = ScreencastState.idle;
  String? _lastError;
  DlnaDevice? _castingTo;
  int _streamPort = 0;
  String? _localIp;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  ScreencastState get state => _state;
  String? get lastError => _lastError;
  DlnaDevice? get castingTo => _castingTo;
  bool get isStreaming => _state == ScreencastState.streaming;

  /// Whether screencast is supported on the current platform.
  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// Callback for UI refresh.
  void Function()? onStateChanged;

  /// Discover DLNA renderers on the local network.
  Future<List<DlnaDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 5),
  }) =>
      _discovery.discover(timeout: timeout);

  /// Discover a device by manual IP entry.
  Future<DlnaDevice?> discoverByIp(String ip) =>
      _discovery.discoverByIp(ip);

  /// Start streaming the desktop to [device].
  ///
  /// Resolution defaults to 1920x1080, framerate to 30 fps.
  Future<void> startCast({
    required DlnaDevice device,
    int width = 1920,
    int height = 1080,
    int framerate = 30,
  }) async {
    if (!isSupported) {
      _lastError = 'Screen casting is only supported on Windows and Linux';
      _setState(ScreencastState.error);
      return;
    }

    await stopCast(); // Clean up any previous session

    _setState(ScreencastState.starting);
    _castingTo = device;
    _lastError = null;

    try {
      _localIp = await LocalMediaServer.getLocalIp();
      if (_localIp == null) {
        throw Exception('Could not determine local IP. Connect to Wi-Fi or LAN.');
      }

      // Bind an HTTP server that will relay FFmpeg's MPEG-TS output to clients.
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _streamPort = _httpServer!.port;

      // We'll pipe FFmpeg's stdout (MPEG-TS) to any connecting HTTP client.
      StreamController<List<int>>? broadcast;

      _httpServer!.listen((request) {
        if (request.uri.path == '/stream') {
          request.response.headers
            ..contentType = ContentType('video', 'mp2t')
            ..set('Connection', 'keep-alive')
            ..set('Cache-Control', 'no-cache')
            ..set('transferMode.dlna.org', 'Streaming');
          request.response.bufferOutput = false;

          broadcast?.stream.listen(
            request.response.add,
            onDone: () => request.response.close(),
            onError: (_) => request.response.close(),
            cancelOnError: true,
          );
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });

      // Build the FFmpeg command for screen + audio capture → MPEG-TS on stdout.
      final args = _buildFfmpegArgs(
        width: width,
        height: height,
        framerate: framerate,
      );

      debugPrint('ScreencastService: ffmpeg ${args.join(' ')}');

      _ffmpeg = await Process.start('ffmpeg', args);
      broadcast = StreamController<List<int>>.broadcast();

      // FFmpeg writes MPEG-TS to stdout → fan out to HTTP clients.
      _ffmpeg!.stdout.listen(
        broadcast.add,
        onDone: () {
          broadcast?.close();
          if (_state == ScreencastState.streaming) {
            _setState(ScreencastState.idle);
          }
        },
        onError: (_) {},
      );

      // Capture stderr for diagnostics.
      final stderrBuf = StringBuffer();
      _stderrSub = _ffmpeg!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((data) {
        stderrBuf.write(data);
        // Once we see "Output #0" or frame data, FFmpeg has started encoding.
        if (_state == ScreencastState.starting &&
            (data.contains('Output #0') || data.contains('frame='))) {
          _setState(ScreencastState.streaming);
        }
      });

      // Small delay to let FFmpeg initialise.
      await Future.delayed(const Duration(seconds: 2));

      if (_state == ScreencastState.starting) {
        // Check if process already exited.
        final exitCode = await _ffmpeg!.exitCode
            .timeout(const Duration(milliseconds: 100), onTimeout: () => -999);
        if (exitCode != -999) {
          throw Exception(
            'FFmpeg exited immediately (code $exitCode). '
            '${stderrBuf.toString().split('\n').last}',
          );
        }
        _setState(ScreencastState.streaming);
      }

      // Tell the DLNA device to play our stream.
      final streamUrl = 'http://$_localIp:$_streamPort/stream';
      await _control.playMedia(
        device: device,
        mediaUrl: streamUrl,
        title: 'Screen Cast',
        mimeType: 'video/mp2t',
      );
    } catch (e) {
      _lastError = e.toString().replaceAll('Exception: ', '');
      _setState(ScreencastState.error);
      await _cleanup();
    }
  }

  /// Stop the current screencast session.
  Future<void> stopCast() async {
    if (_state == ScreencastState.idle) return;
    _setState(ScreencastState.stopping);

    // Tell the TV to stop.
    if (_castingTo != null) {
      try {
        await _control.stop(_castingTo!);
      } catch (_) {}
    }

    await _cleanup();
    _castingTo = null;
    _setState(ScreencastState.idle);
  }

  Future<void> _cleanup() async {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;

    if (_ffmpeg != null) {
      _ffmpeg!.kill(ProcessSignal.sigterm);
      try {
        await _ffmpeg!.exitCode.timeout(const Duration(seconds: 3),
            onTimeout: () {
          _ffmpeg!.kill(ProcessSignal.sigkill);
          return -1;
        });
      } catch (_) {}
      _ffmpeg = null;
    }

    if (_httpServer != null) {
      await _httpServer!.close(force: true);
      _httpServer = null;
    }
  }

  List<String> _buildFfmpegArgs({
    required int width,
    required int height,
    required int framerate,
  }) {
    if (Platform.isWindows) {
      return [
        '-y',
        // Video: GDI screen grab
        '-f', 'gdigrab',
        '-framerate', '$framerate',
        '-video_size', '${width}x$height',
        '-offset_x', '0',
        '-offset_y', '0',
        '-draw_mouse', '1',
        '-i', 'desktop',
        // Audio: DirectShow loopback (system audio)
        // Uses "Stereo Mix" or virtual audio cable if available.
        // If no audio device is found, FFmpeg will still stream video only.
        '-f', 'dshow',
        '-i', 'audio=virtual-audio-capturer',
        // Encoding
        '-c:v', 'libx264',
        '-preset', 'ultrafast',
        '-tune', 'zerolatency',
        '-pix_fmt', 'yuv420p',
        '-g', '${framerate * 2}', // keyframe every 2 seconds
        '-b:v', '4M',
        '-maxrate', '5M',
        '-bufsize', '10M',
        '-c:a', 'aac',
        '-b:a', '128k',
        '-ac', '2',
        '-ar', '44100',
        // Output MPEG-TS to stdout
        '-f', 'mpegts',
        '-',
      ];
    } else {
      // Linux: X11 grab + PulseAudio
      return [
        '-y',
        '-f', 'x11grab',
        '-framerate', '$framerate',
        '-video_size', '${width}x$height',
        '-i', ':0.0',
        '-f', 'pulse',
        '-i', 'default',
        '-c:v', 'libx264',
        '-preset', 'ultrafast',
        '-tune', 'zerolatency',
        '-pix_fmt', 'yuv420p',
        '-g', '${framerate * 2}',
        '-b:v', '4M',
        '-maxrate', '5M',
        '-bufsize', '10M',
        '-c:a', 'aac',
        '-b:a', '128k',
        '-ac', '2',
        '-ar', '44100',
        '-f', 'mpegts',
        '-',
      ];
    }
  }

  void _setState(ScreencastState s) {
    _state = s;
    onStateChanged?.call();
  }

  void dispose() {
    stopCast();
  }
}
