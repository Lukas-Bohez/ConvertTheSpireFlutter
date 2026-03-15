import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'computation_service.dart';
import 'native_miner_service.dart';
import 'qubic_service.dart';

/// Manages Qubic mining for the Support / contribution feature.
///
/// On desktop (Windows / Linux) the service delegates to [NativeMinerService]
/// which runs the official **qli-Client** pool miner as a subprocess.
/// On other platforms it falls back to local simulated crypto tasks so the
/// gamification UI still works.
///
/// All mining earnings go to the developer's Qubic wallet:
///   EBFXZGMDRBEBQAAJDHOTGJPPXEFBUAGHIUKAFVQYFBDGHXVZIKTUTFKBOJIK
class CoordinatorService {
  final ComputationService _compute;

  /// Native pool miner (desktop-only).
  late final NativeMinerService _nativeMiner;

  String _deviceId;

  StreamSubscription? _resultSub;
  StreamSubscription? _minerSub;
  Timer? _localJobTimer;

  bool _enabled = false;
  bool _localMode = false;

  /// Callback for UI refresh.
  void Function()? onStateChanged;

  /// Human-readable connection status for the UI.
  String connectionStatus = 'Disconnected';

  /// Last error, if any.
  String? lastError;

  bool get connected => _nativeMinerActuallyMining || _localMode;
  bool get enabled => _enabled;
  bool get localMode => _localMode;
  String get deviceId => _deviceId;

  /// Whether the native qli-Client miner is active (process alive).
  bool get nativeMinerRunning => _nativeMinerRunning;
  bool get _nativeMinerRunning =>
      _nativeMiner.state == MinerState.running ||
      _nativeMiner.state == MinerState.starting;

  /// Whether the miner is actually producing hashes (not just starting).
  bool get _nativeMinerActuallyMining =>
      _nativeMiner.state == MinerState.running &&
      (_nativeMiner.hashRate > 0 ||
          _nativeMiner.avgHashRate > 0 ||
          _nativeMiner.epoch > 0);

  /// Whether the native mining binary is available for this platform.
  bool get nativeMinerSupported => !kIsWeb && NativeMinerService.isSupported;

  /// Expose the native miner so the UI can read stats directly.
  NativeMinerService get nativeMiner => _nativeMiner;

  CoordinatorService({
    required ComputationService compute,
    String? deviceId,
  })  : _compute = compute,
        _deviceId = deviceId ?? _generateDeviceId() {
    _nativeMiner = NativeMinerService();
    _nativeMiner.onStateChanged = () => onStateChanged?.call();
  }

  static String _generateDeviceId() {
    final rng = Random.secure();
    final bytes = List.generate(8, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ── Enable / Disable ────────────────────────────────────────────────────

  static const _enabledKey = 'coordinator_enabled';

  /// Enable or disable the service.  Persists the choice so streaming can
  /// auto-resume after an app restart.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    _compute.setEnabled(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (_) {}
    if (value) {
      _start();
    } else {
      await _stop();
    }
    onStateChanged?.call();
  }

  /// Restore persisted enabled state.  Call once from the UI after services
  /// are wired up (e.g. in SupportScreen.initState).
  Future<bool> restoreEnabledState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_enabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Start / Stop ────────────────────────────────────────────────────────

  void _start() {
    if (_localMode || _nativeMinerRunning) return;
    if (!_enabled) return;

    if (nativeMinerSupported) {
      _startNativeMiner();
    } else {
      _activateLocalMode();
    }
  }

  Future<void> _startNativeMiner() async {
    connectionStatus = 'Starting pool miner\u2026';
    lastError = null;
    onStateChanged?.call();
    debugPrint('CoordinatorService: starting native qli-Client miner');

    _minerSub?.cancel();
    _minerSub = _nativeMiner.statsStream.listen((stats) {
      connectionStatus = stats.statusMessage;
      // Only propagate errors when they're set; clear when miner clears them.
      lastError = stats.lastError;
      onStateChanged?.call();
    });

    try {
      await _nativeMiner.start();
    } catch (e) {
      lastError = e.toString();
      connectionStatus = 'Failed to start miner';
      onStateChanged?.call();
    }
  }

  /// Restart the miner (e.g. after changing thread count).
  Future<void> restartNativeMiner() async {
    if (!nativeMinerSupported) return;
    await _nativeMiner.stop();
    // stop() already calls killAllInstances(), but belt-and-suspenders:
    await NativeMinerService.killAllInstances();
    _localMode = false;
    // Give the OS time to fully release the process and its resources.
    await Future.delayed(const Duration(seconds: 1));
    if (_enabled) {
      await _startNativeMiner();
    }
  }

  // ── Local fallback mode ─────────────────────────────────────────────────

  /// Activate local mode: generates cryptographic tasks on-device
  /// so the mining feature works on platforms without native miner support.
  void _activateLocalMode() {
    if (_localMode) return;
    _localMode = true;
    connectionStatus = 'Mining locally (simulated)';
    lastError = null;
    onStateChanged?.call();
    debugPrint('CoordinatorService: switched to local simulated mode');
    _startLocalJobGeneration();
  }

  void _startLocalJobGeneration() {
    _localJobTimer?.cancel();
    _localJobTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_enabled || !_localMode) {
        _localJobTimer?.cancel();
        _localJobTimer = null;
        return;
      }
      if (_compute.queuedCount + _compute.activeCount >=
          _compute.maxConcurrent * 2) {
        return; // don't over-fill
      }
      _compute.enqueue(_generateLocalJob());
    });
    // Listen for completed results to track mining stats.
    _resultSub?.cancel();
    _resultSub = _compute.results.listen((result) {
      if (result.type == ComputeJobType.qubicMining) {
        final iters = (result.result['iterations'] as num?)?.toInt() ?? 0;
        _totalHashIterations += iters;
        if (result.result['solved'] == true) {
          _solvedCount++;
        }
        onStateChanged?.call();
      }
    });
    // Also enqueue one right now
    if (_enabled) {
      _compute.enqueue(_generateLocalJob());
    }
  }

  int _localJobCounter = 0;
  int _solvedCount = 0;
  int _totalHashIterations = 0;

  /// Number of PoW solutions found this session.
  int get solvedCount =>
      nativeMinerSupported ? _nativeMiner.solutionsFound : _solvedCount;

  /// Total hash iterations performed this session.
  int get totalHashIterations => _totalHashIterations;

  /// Real-time hash rate (native miner it/s, or local estimate).
  double get hashRate => nativeMinerSupported ? _nativeMiner.hashRate : 0;

  ComputeJob _generateLocalJob() {
    _localJobCounter++;
    final rng = Random();

    // 70 % Qubic-style PoW jobs; 30 % mixed crypto tasks.
    if (rng.nextDouble() < 0.70) {
      final epoch =
          DateTime.now().millisecondsSinceEpoch ~/ 60000; // 1-min epoch
      final difficulty = 12 + rng.nextInt(8);
      final maxIter = 200000 + rng.nextInt(600000);
      return ComputeJob(
        id: 'qubic_${_localJobCounter}_${rng.nextInt(0xFFFF).toRadixString(16)}',
        type: ComputeJobType.qubicMining,
        payload: {
          'wallet_id': QubicService.walletId,
          'epoch': epoch,
          'difficulty': difficulty,
          'max_iterations': maxIter,
        },
        receivedAt: DateTime.now(),
      );
    }

    final types = [
      ComputeJobType.sha256Batch,
      ComputeJobType.primeSearch,
      ComputeJobType.crc32Verify,
    ];
    final type = types[rng.nextInt(types.length)];

    Map<String, dynamic> payload;
    switch (type) {
      case ComputeJobType.sha256Batch:
        final inputs = List.generate(
          100 + rng.nextInt(200),
          (i) =>
              '${QubicService.walletId}:${_localJobCounter}:$i:${rng.nextInt(999999)}',
        );
        payload = {'inputs': inputs};
        break;
      case ComputeJobType.primeSearch:
        final start = 10000 + rng.nextInt(90000);
        payload = {'start': start, 'end': start + 1000 + rng.nextInt(4000)};
        break;
      case ComputeJobType.crc32Verify:
        final data =
            List.generate(500 + rng.nextInt(1500), (_) => rng.nextInt(128))
                .map((c) => String.fromCharCode(c + 32))
                .join();
        payload = {'data': data};
        break;
      default:
        payload = {
          'inputs': ['${QubicService.walletId}:fallback:${_localJobCounter}']
        };
        break;
    }

    return ComputeJob(
      id: 'local_${_localJobCounter}_${rng.nextInt(0xFFFF).toRadixString(16)}',
      type: type,
      payload: payload,
      receivedAt: DateTime.now(),
    );
  }

  // ── Disconnect / dispose ────────────────────────────────────────────────

  Future<void> _stop() async {
    _localJobTimer?.cancel();
    _localJobTimer = null;
    _resultSub?.cancel();
    _resultSub = null;
    _minerSub?.cancel();
    _minerSub = null;

    await _nativeMiner.stop();

    _localMode = false;
    connectionStatus = 'Disconnected';
    onStateChanged?.call();
  }

  void dispose() {
    onStateChanged = null;
    _localJobTimer?.cancel();
    _resultSub?.cancel();
    _minerSub?.cancel();
    _nativeMiner.dispose();
    _stop();
    _compute.dispose();
  }
}
