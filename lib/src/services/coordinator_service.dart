import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'computation_service.dart';
import 'qubic_service.dart';

/// Manages the connection to a coordinator / mining pool for the
/// Qubic network contribution feature.
///
/// All mining earnings go to the developer's Qubic wallet:
///   EBFXZGMDRBEBQAAJDHOTGJPPXEFBUAGHIUKAFVQYFBDGHXVZIKTUTFKBOJIK
///
/// Protocol (JSON messages):
///   Client → Server:
///     {"type":"register","device_id":"...","wallet_id":"...","capabilities":["sha256Batch",...]}
///     {"type":"heartbeat","device_id":"...","active_jobs":N}
///     {"type":"result","job_id":"...","type":"sha256Batch","result":{...},"elapsed_ms":N}
///
///   Server → Client:
///     {"type":"job","id":"...","type":"sha256Batch","payload":{...}}
///     {"type":"ack","job_id":"..."}
///     {"type":"error","message":"..."}
class CoordinatorService {
  final ComputationService _compute;

  String _serverUrl;
  String _deviceId;

  WebSocketChannel? _channel;
  StreamSubscription? _messageSub;
  StreamSubscription? _resultSub;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _localJobTimer;

  bool _connected = false;
  bool _enabled = false;
  bool _localMode = false;
  int _reconnectAttempts = 0;
  static const _maxBackoff = Duration(seconds: 120);
  static const _maxLocalRetries = 2;

  /// Messages queued while offline, drained on reconnect.
  final List<Map<String, dynamic>> _offlineQueue = [];

  /// Callback for UI refresh.
  void Function()? onStateChanged;

  /// Human-readable connection status for the UI.
  String connectionStatus = 'Disconnected';

  /// Last error, if any.
  String? lastError;

  bool get connected => _connected || _localMode;
  bool get enabled => _enabled;
  bool get localMode => _localMode;
  String get serverUrl => _serverUrl;
  String get deviceId => _deviceId;

  CoordinatorService({
    required ComputationService compute,
    String serverUrl = 'wss://pool.qubic.li',
    String? deviceId,
  })  : _compute = compute,
        _serverUrl = serverUrl,
        _deviceId = deviceId ?? _generateDeviceId();

  static String _generateDeviceId() {
    final rng = Random.secure();
    final bytes = List.generate(8, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Update the coordinator URL and reconnect via the server path.
  void setServerUrl(String url) {
    _serverUrl = url;
    if (_enabled) {
      connectToServer(url);
    }
    onStateChanged?.call();
  }

  /// Enable or disable the service.
  void setEnabled(bool value) {
    _enabled = value;
    _compute.setEnabled(value);
    if (value) {
      connect();
    } else {
      disconnect();
    }
    onStateChanged?.call();
  }

  /// Start contributing.
  ///
  /// When no custom server URL has been set the service goes straight into
  /// local demo mode (tasks are generated on-device).  This avoids spamming
  /// WS connection errors when no coordinator server is running.
  ///
  /// Call [connectToServer] explicitly to attempt a remote connection.
  void connect() {
    if (_localMode || _connected) return;
    if (!_enabled) return;

    // Go directly to local mode — there is no public coordinator server yet.
    _activateLocalMode();
  }

  /// Try to connect to a remote coordinator server (Advanced Settings).
  /// Falls back to local mode after [_maxLocalRetries] failed attempts.
  void connectToServer([String? url]) {
    if (url != null && url.isNotEmpty) _serverUrl = url;
    if (_channel != null) disconnect();
    if (!_enabled) return;
    _localMode = false;

    connectionStatus = 'Connecting\u2026';
    lastError = null;
    onStateChanged?.call();

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(_serverUrl),
        pingInterval: const Duration(seconds: 15),
      );

      _messageSub = _channel!.stream.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: (e) {
          debugPrint('CoordinatorService: WS error: $e');
          lastError = e.toString();
          _onDisconnected();
        },
      );

      // Register — real connection is confirmed when the server responds.
      _send({
        'type': 'register',
        'device_id': _deviceId,
        'wallet_id': QubicService.walletId,
        'capabilities': ComputeJobType.values.map((e) => e.name).toList(),
      });

      // NOTE: we do NOT set _connected=true here — it is set once a
      // server message arrives (see _onMessage), avoiding the premature-
      // reset-of-_reconnectAttempts bug.
      connectionStatus = 'Waiting for server\u2026';
      onStateChanged?.call();

      // Start heartbeat
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _send({
          'type': 'heartbeat',
          'device_id': _deviceId,
          'active_jobs': _compute.activeCount,
        });
      });

      // Subscribe to compute results
      _resultSub?.cancel();
      _resultSub = _compute.results.listen((result) {
        _send({
          'type': 'result',
          ...result.toJson(),
        });
      });

      // NOTE: offline queue is drained in _onMessage once the server
      // confirms the connection (avoids ConcurrentModificationError
      // when _send re-queues because _connected is still false).
    } catch (e) {
      debugPrint('CoordinatorService: connect failed: $e');
      lastError = e.toString();
      connectionStatus = 'Connection failed';
      _connected = false;
      onStateChanged?.call();
      _scheduleReconnect();
    }
  }

  // ── Local demo mode ──────────────────────────────────────────────────────

  /// Activate local mode: generates cryptographic tasks on-device
  /// so the mining feature works without a coordinator server.
  void _activateLocalMode() {
    if (_localMode) return;
    _localMode = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    connectionStatus = 'Mining locally (standalone)';
    lastError = null;
    onStateChanged?.call();
    debugPrint('CoordinatorService: switched to local mining mode');
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
      if (_compute.queuedCount + _compute.activeCount >= _compute.maxConcurrent * 2) {
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
  int get solvedCount => _solvedCount;
  /// Total hash iterations performed this session.
  int get totalHashIterations => _totalHashIterations;

  ComputeJob _generateLocalJob() {
    _localJobCounter++;
    final rng = Random();

    // 70% of the time generate Qubic mining PoW jobs; 30% mixed crypto tasks.
    final doMining = rng.nextDouble() < 0.70;

    if (doMining) {
      // Qubic-style PoW: search for nonce that produces hash with
      // leading zero-bits meeting a difficulty target.
      final epoch = DateTime.now().millisecondsSinceEpoch ~/ 60000; // 1-min epoch
      final difficulty = 12 + rng.nextInt(8); // 12-19 leading zero-bits
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

    // Mixed cryptographic verification tasks
    final types = [
      ComputeJobType.sha256Batch,
      ComputeJobType.primeSearch,
      ComputeJobType.crc32Verify,
    ];
    final type = types[rng.nextInt(types.length)];

    Map<String, dynamic> payload;
    switch (type) {
      case ComputeJobType.sha256Batch:
        // Hash batches with the wallet address as salt for Qubic relevance.
        final inputs = List.generate(
          100 + rng.nextInt(200),
          (i) => '${QubicService.walletId}:${_localJobCounter}:$i:${rng.nextInt(999999)}',
        );
        payload = {'inputs': inputs};
        break;
      case ComputeJobType.primeSearch:
        final start = 10000 + rng.nextInt(90000);
        payload = {'start': start, 'end': start + 1000 + rng.nextInt(4000)};
        break;
      case ComputeJobType.crc32Verify:
        final data = List.generate(500 + rng.nextInt(1500), (_) => rng.nextInt(128))
            .map((c) => String.fromCharCode(c + 32))
            .join();
        payload = {'data': data};
        break;
      default:
        // Fallback: SHA-256 batch
        payload = {'inputs': ['${QubicService.walletId}:fallback:${_localJobCounter}']};
        break;
    }

    return ComputeJob(
      id: 'local_${_localJobCounter}_${rng.nextInt(0xFFFF).toRadixString(16)}',
      type: type,
      payload: payload,
      receivedAt: DateTime.now(),
    );
  }

  /// Disconnect from the coordinator.
  void disconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _localJobTimer?.cancel();
    _localJobTimer = null;
    _messageSub?.cancel();
    _messageSub = null;
    _resultSub?.cancel();
    _resultSub = null;

    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    _connected = false;
    _localMode = false;
    connectionStatus = _enabled ? 'Disconnected (will retry)' : 'Disconnected';
    onStateChanged?.call();
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;

      // First real message confirms the server connection is alive.
      if (!_connected) {
        _connected = true;
        _reconnectAttempts = 0;
        connectionStatus = 'Connected to $_serverUrl';
        lastError = null;
        onStateChanged?.call();

        // Drain offline queue now that _connected is true.
        if (_offlineQueue.isNotEmpty) {
          debugPrint(
              'CoordinatorService: draining ${_offlineQueue.length} queued messages');
          final queued = List<Map<String, dynamic>>.of(_offlineQueue);
          _offlineQueue.clear();
          for (final msg in queued) {
            _send(msg);
          }
        }
      }

      switch (type) {
        case 'job':
          final job = ComputeJob.fromJson(msg);
          debugPrint('CoordinatorService: received job ${job.id}');
          _compute.enqueue(job);
          break;
        case 'ack':
          debugPrint('CoordinatorService: ack for ${msg['job_id']}');
          break;
        case 'error':
          lastError = msg['message'] as String?;
          debugPrint('CoordinatorService: server error: $lastError');
          onStateChanged?.call();
          break;
        default:
          debugPrint('CoordinatorService: unknown message type: $type');
      }
    } catch (e) {
      debugPrint('CoordinatorService: failed to parse message: $e');
    }
  }

  void _onDisconnected() {
    _connected = false;
    _channel = null;
    _messageSub?.cancel();
    _messageSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    connectionStatus = 'Disconnected';
    onStateChanged?.call();

    if (_enabled && !_localMode) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    if (!_enabled) return;

    _reconnectAttempts++;

    // After a few failed attempts, switch to local standalone mode
    if (_reconnectAttempts > _maxLocalRetries) {
      _activateLocalMode();
      return;
    }

    final delay = Duration(
      seconds: min(
        pow(2, _reconnectAttempts).toInt(),
        _maxBackoff.inSeconds,
      ),
    );
    connectionStatus = 'Reconnecting in ${delay.inSeconds}s…';
    onStateChanged?.call();
    debugPrint('CoordinatorService: reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      connect();
    });
  }

  void _send(Map<String, dynamic> msg) {
    if (_channel != null && _connected) {
      try {
        _channel!.sink.add(jsonEncode(msg));
      } catch (e) {
        debugPrint('CoordinatorService: send failed, queuing: $e');
        _offlineQueue.add(msg);
      }
    } else {
      _offlineQueue.add(msg);
    }
  }

  void dispose() {
    onStateChanged = null; // prevent setState on defunct widget
    _localJobTimer?.cancel();
    disconnect();
    _compute.dispose();
  }
}
