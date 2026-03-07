import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'qubic_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

enum MinerState { stopped, downloading, extracting, starting, running, error }

class MinerStats {
  final double hashRate;
  final double avgHashRate;
  final int solutionsFound;
  final int solutionsSubmitted;
  final int solutionsRejected;
  final int epoch;
  final String statusMessage;
  final MinerState state;
  final double downloadProgress;
  final String? lastError;

  const MinerStats({
    this.hashRate = 0,
    this.avgHashRate = 0,
    this.solutionsFound = 0,
    this.solutionsSubmitted = 0,
    this.solutionsRejected = 0,
    this.epoch = 0,
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
    if (!kIsWeb && Platform.isWindows) {
      return 'https://dl.qubic.li/downloads/qli-Client-$clientVersion-Windows-x64.zip';
    }
    if (!kIsWeb && Platform.isLinux) {
      return 'https://dl.qubic.li/downloads/qli-Client-$clientVersion-Linux-x64.tar.gz';
    }
    throw UnsupportedError('Mining not supported on this platform');
  }

  static String get _binaryName =>
      !kIsWeb && Platform.isWindows ? 'qli-Client.exe' : 'qli-Client';

  /// Whether the current platform can run the native miner.
  static bool get isSupported =>
      !_isTestMode && !kIsWeb && (Platform.isWindows || Platform.isLinux);

  // For unit-testing without dart:io platform checks.
  static bool _isTestMode = false;

  // ── State ────────────────────────────────────────────────────────────────
  Process? _process;
  MinerState _state = MinerState.stopped;
  double _hashRate = 0;
  double _avgHashRate = 0;
  int _solutionsFound = 0;
  int _solutionsSubmitted = 0;
  int _solutionsRejected = 0;
  int _epoch = 0;
  String? _lastError;
  String _statusMessage = 'Stopped';
  double _downloadProgress = 0;
  int _cpuThreads = 2;
  bool _disposed = false;
  Timer? _statsThrottle;
  bool _statsPending = false;
  Timer? _connectionTimeout;
  int _restartCount = 0;
  bool _everConnected = false;

  final StreamController<MinerStats> _statsController =
      StreamController<MinerStats>.broadcast();

  /// Fires whenever mining statistics change.
  Stream<MinerStats> get statsStream => _statsController.stream;

  MinerState get state => _state;
  double get hashRate => _hashRate;
  double get avgHashRate => _avgHashRate;
  int get solutionsFound => _solutionsFound;
  int get solutionsSubmitted => _solutionsSubmitted;
  int get solutionsRejected => _solutionsRejected;
  int get epoch => _epoch;
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
    _persistThreads();
  }

  static const _threadsKey = 'miner_cpu_threads';

  Future<void> _persistThreads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_threadsKey, _cpuThreads);
    } catch (e) {
      debugPrint('Failed to persist thread count: $e');
    }
  }

  /// Load persisted settings (thread count, etc.) from SharedPreferences.
  Future<void> loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_threadsKey);
      if (saved != null) {
        _cpuThreads = saved.clamp(1, Platform.numberOfProcessors);
      }
    } catch (e) {
      debugPrint('Failed to load saved miner settings: $e');
    }
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
    if (_state == MinerState.running || _state == MinerState.starting) {
      // Kill the existing process before starting a new one.
      await stop();
    }

    // Also kill any orphaned process we still hold a reference to.
    if (_process != null) {
      await _killProcess(_process!);
      _process = null;
    }

    // Kill ALL lingering qli-Client instances before starting fresh.
    await killAllInstances();

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
          'amountOfThreads': t,
          'idling': false,
          'trainer': {
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

      // Set miner to BelowNormal priority so downloads and app stay responsive.
      if (Platform.isWindows) {
        try {
          await Process.run('wmic', [
            'process',
            'where',
            'ProcessId=${_process!.pid}',
            'CALL',
            'SetPriority',
            '16384',  // BelowNormal
          ]);
        } catch (_) {}
      }

      _setState(MinerState.running, msg: 'Connecting to pool\u2026');

      // Start a connection timeout — restart if stuck on "starting" for too long.
      _connectionTimeout?.cancel();
      _connectionTimeout = Timer(const Duration(seconds: 90), () {
        if (_disposed) return;
        if (_hashRate <= 0 && _avgHashRate <= 0 && _state == MinerState.running) {
          debugPrint('NativeMinerService: connection timeout — restarting');
          _lastError = 'Connection timed out. Restarting\u2026';
          _restartCount++;
          if (_restartCount <= 3) {
            _autoRestart();
          } else {
            _setState(MinerState.error,
                msg: 'Unable to connect after multiple attempts');
          }
        }
      });

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

  /// Auto-restart the miner after a connection timeout.
  Future<void> _autoRestart() async {
    _connectionTimeout?.cancel();
    final proc = _process;
    _process = null;
    if (proc != null) {
      await _killProcess(proc);
    }
    await killAllInstances();
    _hashRate = 0;
    _avgHashRate = 0;
    _setState(MinerState.starting, msg: 'Restarting miner\u2026');
    await Future.delayed(const Duration(seconds: 3));
    if (_disposed || _state == MinerState.stopped) return;
    await start();
  }

  Future<void> stop() async {
    _connectionTimeout?.cancel();
    _hashRate = 0;
    _restartCount = 0;
    _everConnected = false;
    final proc = _process;
    _process = null;
    if (proc != null) {
      await _killProcess(proc);
    }
    // Kill any orphaned instances that weren't tracked by this service.
    await killAllInstances();
    _setState(MinerState.stopped, msg: 'Stopped');
  }

  /// Kill ALL qli-Client processes on the system, not just the tracked one.
  /// This handles orphaned processes from previous runs or restarts.
  static Future<void> killAllInstances() async {
    try {
      if (!kIsWeb && Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/IM', 'qli-Client.exe']);
      } else if (!kIsWeb && Platform.isLinux) {
        await Process.run('pkill', ['-f', 'qli-Client']);
      }
    } catch (e) {
      debugPrint('killAllInstances: $e');
    }
  }

  /// Force-kill a miner process and all its children.
  Future<void> _killProcess(Process proc) async {
    final pid = proc.pid;
    debugPrint('NativeMinerService: killing process tree (PID $pid)');
    try {
      if (Platform.isWindows) {
        // taskkill /F /T kills the entire process tree on Windows.
        await Process.run('taskkill', ['/F', '/T', '/PID', '$pid']);
      } else {
        // Kill the process group on Linux.
        proc.kill(ProcessSignal.sigterm);
        // Give it a moment to shut down gracefully.
        final exited = await proc.exitCode
            .timeout(const Duration(seconds: 3), onTimeout: () => -1);
        if (exited == -1) {
          // Force kill if it didn't exit.
          proc.kill(ProcessSignal.sigkill);
        }
      }
    } catch (e) {
      debugPrint('NativeMinerService: kill failed: $e');
      // Last resort: try kill() directly.
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
  }

  // ── Output parsing ──────────────────────────────────────────────────────

  // Strip ANSI escape codes (coloured output from qli-Client)
  static final _ansiRe = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

  // Matches: "167 it/s", "13.1K it/s" (first occurrence = current rate)
  static final _hashRateRe =
      RegExp(r'(\d+(?:[.,]\d+)?)\s*([KkMmGg])?\s*(?:it/s|iterations/s|sol/s|h/s)', caseSensitive: false);
  // Matches: "163 avg it/s", "13.1K avg it/s"
  static final _avgRateRe =
      RegExp(r'(\d+(?:[.,]\d+)?)\s*([KkMmGg])?\s*avg\s*(?:it/s|h/s)', caseSensitive: false);
  // Matches: "SOLS: 0/0 (R:0)" → found/submitted (rejected)
  static final _solsRe =
      RegExp(r'SOLS:\s*(\d+)/(\d+)\s*\(R:(\d+)\)');
  // Matches: "E:202 |" → epoch number
  static final _epochRe = RegExp(r'E:(\d+)\s*\|');
  // Matches explicit solution messages from qli-Client
  static final _solutionRe =
      RegExp(r'solution\s+(?:found|submitted|accepted)', caseSensitive: false);

  // Known XMRig/qli-Client warnings that are NOT fatal errors
  static const _ignoredWarnings = [
    'failed to apply msr mod',
    'huge pages',
    'hashrate will be low',
    'msr kernel module',
    'randomx init',
  ];

  /// Parse a rate match that may contain K/M/G suffix.
  static double _parseRateMatch(Match m) {
    final raw = m.group(1)!.replaceAll(',', '.');
    var value = double.tryParse(raw) ?? 0;
    final suffix = m.group(2)?.toUpperCase();
    if (suffix == 'K') value *= 1000;
    else if (suffix == 'M') value *= 1000000;
    else if (suffix == 'G') value *= 1000000000;
    return value;
  }

  void _parseLine(String line) {
    if (_disposed) return;
    // Strip ANSI escape codes that break regex parsing.
    line = line.replaceAll(_ansiRe, '');
    debugPrint('MINER: $line');

    // ── Parse epoch line: E:202 | SOLS: 0/0 (R:0) | 167 it/s | 163 avg it/s
    final epochMatch = _epochRe.firstMatch(line);
    if (epochMatch != null) {
      _epoch = int.tryParse(epochMatch.group(1)!) ?? _epoch;
    }

    // ── Parse SOLS: X/Y (R:Z)
    final solsMatch = _solsRe.firstMatch(line);
    if (solsMatch != null) {
      _solutionsFound = int.tryParse(solsMatch.group(1)!) ?? _solutionsFound;
      _solutionsSubmitted = int.tryParse(solsMatch.group(2)!) ?? _solutionsSubmitted;
      _solutionsRejected = int.tryParse(solsMatch.group(3)!) ?? _solutionsRejected;
    }

    // ── Parse hash rate: current it/s (handles K/M/G suffixes)
    final hashMatch = _hashRateRe.firstMatch(line);
    if (hashMatch != null) {
      _hashRate = _parseRateMatch(hashMatch);
    }

    // ── Parse average hash rate: avg it/s
    final avgMatch = _avgRateRe.firstMatch(line);
    if (avgMatch != null) {
      _avgHashRate = _parseRateMatch(avgMatch);
    }

    // ── Explicit solution messages
    if (_solutionRe.hasMatch(line)) {
      _solutionsFound++;
    }

    // ── Connection / status messages
    final lower = line.toLowerCase();

    // Epoch line — actively mining if any rate > 0
    if (epochMatch != null && _hashRate > 0) {
      if (!_everConnected) {
        _everConnected = true;
        _connectionTimeout?.cancel();
        _restartCount = 0;
      }
      _statusMessage = 'Mining \u2022 Epoch $_epoch \u2022 ${_hashRate.round()} it/s';
    } else if (epochMatch != null && _avgHashRate > 0) {
      _statusMessage = 'Mining \u2022 Epoch $_epoch \u2022 warming up';
    } else if (epochMatch != null) {
      _statusMessage = 'Mining \u2022 Epoch $_epoch \u2022 initializing\u2026';
    } else if (lower.contains('use pool') || lower.contains('connected')) {
      _statusMessage = 'Connected to pool';
    } else if (lower.contains('cpu') && lower.contains('ready')) {
      _statusMessage = 'CPU trainer ready, mining\u2026';
    } else if (lower.contains('idle') || lower.contains('waiting')) {
      _statusMessage = 'Idle (waiting for next round)';
    } else if (lower.contains('unable to connect') ||
               lower.contains('connection refused') ||
               lower.contains('could not connect') ||
               lower.contains('no connection')) {
      _lastError = line.length > 120 ? '${line.substring(0, 120)}\u2026' : line;
      _statusMessage = 'Unable to connect to pool';
      // Trigger auto-restart if we haven't exceeded retry limit
      if (!_everConnected && _restartCount <= 3) {
        _connectionTimeout?.cancel();
        _restartCount++;
        debugPrint('NativeMinerService: pool connection failed, auto-restart #$_restartCount');
        _autoRestart();
      } else if (_restartCount > 3) {
        _setState(MinerState.error, msg: 'Unable to connect after multiple attempts');
      }
    } else if (lower.contains('error') || lower.contains('fail')) {
      // Filter known XMRig performance warnings
      final isKnownWarning = _ignoredWarnings.any((w) => lower.contains(w));
      if (!isKnownWarning) {
        _lastError = line.length > 120 ? '${line.substring(0, 120)}\u2026' : line;
        if (lower.contains('authentication')) {
          _statusMessage = 'Auth error \u2014 check pool settings';
        }
      }
    }

    _emitStats();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _setState(MinerState s, {String? msg}) {
    _state = s;
    if (msg != null) _statusMessage = msg;
    // State transitions are important — emit immediately.
    _emitStatsNow();
  }

  /// Throttled emit: batches rapid updates into at most one per second.
  void _emitStats() {
    if (_disposed || _statsController.isClosed) return;
    if (_statsThrottle?.isActive ?? false) {
      _statsPending = true;
      return;
    }
    _emitStatsNow();
    _statsThrottle = Timer(const Duration(seconds: 1), () {
      if (_statsPending) {
        _statsPending = false;
        _emitStatsNow();
      }
    });
  }

  void _emitStatsNow() {
    if (_disposed || _statsController.isClosed) return;
    _statsPending = false;
    _statsController.add(MinerStats(
      hashRate: _hashRate,
      avgHashRate: _avgHashRate,
      solutionsFound: _solutionsFound,
      solutionsSubmitted: _solutionsSubmitted,
      solutionsRejected: _solutionsRejected,
      epoch: _epoch,
      statusMessage: _statusMessage,
      state: _state,
      downloadProgress: _downloadProgress,
      lastError: _lastError,
    ));
    onStateChanged?.call();
  }

  void dispose() {
    _disposed = true;
    _statsThrottle?.cancel();
    _connectionTimeout?.cancel();
    // Use synchronous kill for dispose — can't await here.
    final proc = _process;
    _process = null;
    if (proc != null) {
      try {
        if (Platform.isWindows) {
          Process.run('taskkill', ['/F', '/T', '/PID', '${proc.pid}']);
        } else {
          proc.kill(ProcessSignal.sigkill);
        }
      } catch (_) {}
    }
    // Kill all orphaned instances too.
    killAllInstances();
    _hashRate = 0;
    _state = MinerState.stopped;
    if (!_statsController.isClosed) _statsController.close();
    onStateChanged = null;
  }
}
