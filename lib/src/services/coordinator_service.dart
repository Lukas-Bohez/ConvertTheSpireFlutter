import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'computation_service.dart';

/// Manages the WebSocket connection to a coordinator server for the
/// distributed computing volunteer network.
///
/// Protocol (JSON messages):
///   Client → Server:
///     {"type":"register","device_id":"...","capabilities":["sha256Batch",...]}
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
    String serverUrl = 'ws://localhost:8765',
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

      // Drain offline queue
      if (_offlineQueue.isNotEmpty) {
        debugPrint(
            'CoordinatorService: draining ${_offlineQueue.length} queued messages');
        for (final msg in _offlineQueue) {
          _send(msg);
        }
        _offlineQueue.clear();
      }
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

  /// Activate local mode: generates lightweight academic tasks on-device
  /// so the volunteer feature works without a coordinator server.
  void _activateLocalMode() {
    if (_localMode) return;
    _localMode = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    connectionStatus = 'Running locally (standalone)';
    lastError = null;
    onStateChanged?.call();
    debugPrint('CoordinatorService: switched to local demo mode');
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
    // Also enqueue one right now
    if (_enabled) {
      _compute.enqueue(_generateLocalJob());
    }
  }

  int _localJobCounter = 0;

  ComputeJob _generateLocalJob() {
    _localJobCounter++;
    final rng = Random();
    final types = ComputeJobType.values;
    final type = types[rng.nextInt(types.length)];

    Map<String, dynamic> payload;
    switch (type) {
      case ComputeJobType.sha256Batch:
        final inputs = List.generate(
          50 + rng.nextInt(150),
          (i) => 'data_block_${_localJobCounter}_$i\_${rng.nextInt(999999)}',
        );
        payload = {'inputs': inputs};
        break;
      case ComputeJobType.primeSearch:
        final start = 1000 + rng.nextInt(90000);
        payload = {'start': start, 'end': start + 500 + rng.nextInt(2000)};
        break;
      case ComputeJobType.matrixMultiply:
        final n = 10 + rng.nextInt(20);
        payload = {
          'a': List.generate(n, (_) => List.generate(n, (_) => rng.nextDouble() * 10)),
          'b': List.generate(n, (_) => List.generate(n, (_) => rng.nextDouble() * 10)),
        };
        break;
      case ComputeJobType.crc32Verify:
        final data = List.generate(200 + rng.nextInt(800), (_) => rng.nextInt(128))
            .map((c) => String.fromCharCode(c + 32))
            .join();
        payload = {'data': data};
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
