import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

import 'qubic_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

enum MinerState { stopped, downloading, extracting, starting, running, error }

class MinerStats {
  final double hashRate;
  final int solutionsFound;
  final String statusMessage;
  final MinerState state;
  final double downloadProgress;
  final String? lastError;

  const MinerStats({
    this.hashRate = 0,
    this.solutionsFound = 0,
    this.statusMessage = 'Stopped',
    this.state = MinerState.stopped,
    this.downloadProgress = 0,
    this.lastError,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// NativeMinerService — manages the qli-Client subprocess for real Qubic mining
// ─────────────────────────────────────────────────────────────────────────────

/// Downloads, configures, and runs the official qli-Client from qubic.li
/// as a background subprocess.  Uses **registerless pool mining** — only the
/// Qubic wallet address is required (no access-token signup).
///
/// Supports Windows and Linux.  Unsupported platforms (Android/iOS/Web/macOS)
/// should fall back to simulated local work.
class NativeMinerService {
  // ── Constants ────────────────────────────────────────────────────────────
  static const clientVersion = '3.5.2';

  static String get _downloadUrl {
    if (Platform.isWindows) {
      return 'https://dl.qubic.li/downloads/qli-Client-$clientVersion-Windows-x64.zip';
    }
    if (Platform.isLinux) {
      return 'https://dl.qubic.li/downloads/qli-Client-$clientVersion-Linux-x64.tar.gz';
    }
    throw UnsupportedError('Mining not supported on ${Platform.operatingSystem}');
  }

  static String get _binaryName =>
      Platform.isWindows ? 'qli-Client.exe' : 'qli-Client';

  /// Whether the current platform can run the native miner.
  static bool get isSupported =>
      !_isTestMode && (Platform.isWindows || Platform.isLinux);

  // For unit-testing without dart:io platform checks.
  static bool _isTestMode = false;

  // ── State ────────────────────────────────────────────────────────────────
  Process? _process;
  MinerState _state = MinerState.stopped;
  double _hashRate = 0;
  int _solutionsFound = 0;
  String? _lastError;
  String _statusMessage = 'Stopped';
  double _downloadProgress = 0;
  int _cpuThreads = 2;
  bool _disposed = false;

  final StreamController<MinerStats> _statsController =
      StreamController<MinerStats>.broadcast();

  /// Fires whenever mining statistics change.
  Stream<MinerStats> get statsStream => _statsController.stream;

  MinerState get state => _state;
  double get hashRate => _hashRate;
  int get solutionsFound => _solutionsFound;
  String? get lastError => _lastError;
  String get statusMessage => _statusMessage;
  double get downloadProgress => _downloadProgress;
  int get cpuThreads => _cpuThreads;
  bool get isRunning => _state == MinerState.running;

  /// Optional callback for external UI refresh.
  void Function()? onStateChanged;

  // ── Configuration ────────────────────────────────────────────────────────

  void setCpuThreads(int threads) {
    _cpuThreads = threads.clamp(1, Platform.numberOfProcessors);
  }

  // ── Miner directory ──────────────────────────────────────────────────────

  String? _minerDirCache;

  Future<String> _getMinerDir() async {
    if (_minerDirCache != null) return _minerDirCache!;
    final appDir = await getApplicationSupportDirectory();
    final minerDir = Directory('${appDir.path}${Platform.pathSeparator}qubic_miner');
    if (!minerDir.existsSync()) {
      minerDir.createSync(recursive: true);
    }
    _minerDirCache = minerDir.path;
    return _minerDirCache!;
  }

  /// Whether the qli-Client binary already exists on disk.
  Future<bool> isMinerInstalled() async {
    final dir = await _getMinerDir();
    return File('$dir${Platform.pathSeparator}$_binaryName').existsSync();
  }

  // ── Download & extract ───────────────────────────────────────────────────

  Future<void> downloadMiner({void Function(double)? onProgress}) async {
    _setState(MinerState.downloading, msg: 'Downloading mining client\u2026');

    try {
      final dir = await _getMinerDir();
      final url = _downloadUrl;
      final archiveName = url.split('/').last;
      final archivePath = '$dir${Platform.pathSeparator}$archiveName';

      // Streaming download with progress.
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      final totalBytes = response.contentLength;
      int receivedBytes = 0;
      final sink = File(archivePath).openWrite();

      await for (final chunk in response) {
        receivedBytes += chunk.length;
        sink.add(chunk);
        if (totalBytes > 0) {
          _downloadProgress = receivedBytes / totalBytes;
          onProgress?.call(_downloadProgress);
          _emitStats();
        }
      }
      await sink.flush();
      await sink.close();
      client.close();

      // Extract archive.
      _setState(MinerState.extracting, msg: 'Extracting\u2026');

      if (Platform.isWindows) {
        final result = await Process.run(
          'tar',
          ['-xf', archivePath, '-C', dir],
        );
        if (result.exitCode != 0) {
          throw Exception('Extraction failed: ${result.stderr}');
        }
      } else {
        final result = await Process.run(
          'tar',
          ['-xzf', archivePath, '-C', dir],
        );
        if (result.exitCode != 0) {
          throw Exception('Extraction failed: ${result.stderr}');
        }
        // Make binary executable.
        await Process.run(
          'chmod',
          ['+x', '$dir${Platform.pathSeparator}$_binaryName'],
        );
      }

      // Remove the archive.
      try {
        File(archivePath).deleteSync();
      } catch (_) {}

      _downloadProgress = 1.0;
      _setState(MinerState.stopped, msg: 'Mining client ready');
    } catch (e) {
      _lastError = e.toString();
      _setState(MinerState.error, msg: 'Download failed');
      rethrow;
    }
  }

  // ── Start / Stop ────────────────────────────────────────────────────────

  Future<void> start({String? walletId, int? threads}) async {
    if (!isSupported) {
      _lastError = 'Mining not supported on ${Platform.operatingSystem}';
      _setState(MinerState.error, msg: _lastError!);
      return;
    }
    if (_state == MinerState.running || _state == MinerState.starting) return;

    final wallet = walletId ?? QubicService.walletId;
    final t = threads ?? _cpuThreads;

    // Ensure the binary is present.
    if (!await isMinerInstalled()) {
      try {
        await downloadMiner();
      } catch (_) {
        return; // state already set to error
      }
    }

    _setState(MinerState.starting, msg: 'Starting miner\u2026');
    _solutionsFound = 0;
    _hashRate = 0;

    try {
      final dir = await _getMinerDir();
      final binaryPath = '$dir${Platform.pathSeparator}$_binaryName';

      // Write an appsettings.json for registerless pool mining.
      final settings = const JsonEncoder.withIndent('  ').convert({
        'Settings': {
          'payoutId': wallet,
          'alias': 'ConvertTheSpire',
          'pps': true, // Pay-Per-Share for smaller setups
          'trainer': {
            'cpuThreads': t,
            'cpu': true,
            'gpu': false,
          },
        },
      });
      File('$dir${Platform.pathSeparator}appsettings.json')
          .writeAsStringSync(settings);

      _process = await Process.start(
        binaryPath,
        [],
        workingDirectory: dir,
        mode: ProcessStartMode.normal,
      );

      _setState(MinerState.running, msg: 'Connecting to pool\u2026');

      // Listen to stdout / stderr.
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_parseLine, onError: (_) {});
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_parseLine, onError: (_) {});

      // Handle process exit.
      _process!.exitCode.then((code) {
        if (_disposed) return;
        debugPrint('NativeMinerService: process exited with code $code');
        _hashRate = 0;
        if (_state != MinerState.stopped) {
          _setState(
            code == 0 ? MinerState.stopped : MinerState.error,
            msg: code == 0 ? 'Stopped' : 'Crashed (exit $code)',
          );
        }
      });
    } catch (e) {
      _lastError = e.toString();
      _setState(MinerState.error, msg: 'Failed to start');
    }
  }

  void stop() {
    _hashRate = 0;
    if (_process != null) {
      try {
        if (Platform.isWindows) {
          // Windows doesn't support SIGINT for child processes reliably.
          _process!.kill(ProcessSignal.sigterm);
        } else {
          _process!.kill(ProcessSignal.sigint);
        }
      } catch (e) {
        debugPrint('NativeMinerService: kill failed: $e');
      }
      _process = null;
    }
    _setState(MinerState.stopped, msg: 'Stopped');
  }

  // ── Output parsing ──────────────────────────────────────────────────────

  static final _hashRateRe =
      RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:it/s|iterations/s|sol/s)', caseSensitive: false);
  static final _avgRateRe =
      RegExp(r'avg[:\s]+(\d+(?:[.,]\d+)?)\s*(?:it/s)?', caseSensitive: false);
  static final _solutionRe =
      RegExp(r'solution\s+(?:found|submitted|accepted)', caseSensitive: false);

  void _parseLine(String line) {
    if (_disposed) return;
    debugPrint('MINER: $line');

    // Hash rate
    final hashMatch = _hashRateRe.firstMatch(line) ?? _avgRateRe.firstMatch(line);
    if (hashMatch != null) {
      final raw = hashMatch.group(1)!.replaceAll(',', '.');
      _hashRate = double.tryParse(raw) ?? _hashRate;
    }

    // Solutions
    if (_solutionRe.hasMatch(line)) {
      _solutionsFound++;
    }

    // Connection / status messages
    final lower = line.toLowerCase();
    if (lower.contains('connected')) {
      _statusMessage = 'Mining (connected to pool)';
    } else if (lower.contains('training') || lower.contains('running')) {
      _statusMessage = 'Mining\u2026';
    } else if (lower.contains('idle') || lower.contains('waiting')) {
      _statusMessage = 'Idle (epoch gap)';
    } else if (lower.contains('error') || lower.contains('fail')) {
      // Surface errors but don't change state for transient issues.
      _lastError = line.length > 120 ? '${line.substring(0, 120)}\u2026' : line;
      if (lower.contains('authentication')) {
        _statusMessage = 'Auth error \u2014 check pool settings';
      }
    }

    _emitStats();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _setState(MinerState s, {String? msg}) {
    _state = s;
    if (msg != null) _statusMessage = msg;
    _emitStats();
  }

  void _emitStats() {
    if (_disposed || _statsController.isClosed) return;
    _statsController.add(MinerStats(
      hashRate: _hashRate,
      solutionsFound: _solutionsFound,
      statusMessage: _statusMessage,
      state: _state,
      downloadProgress: _downloadProgress,
      lastError: _lastError,
    ));
    onStateChanged?.call();
  }

  void dispose() {
    _disposed = true;
    stop();
    if (!_statsController.isClosed) _statsController.close();
    onStateChanged = null;
  }
}
