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

  bool _connected = false;
  bool _enabled = false;
  int _reconnectAttempts = 0;
  static const _maxBackoff = Duration(seconds: 120);

  /// Messages queued while offline, drained on reconnect.
  final List<Map<String, dynamic>> _offlineQueue = [];

  /// Callback for UI refresh.
  void Function()? onStateChanged;

  /// Human-readable connection status for the UI.
  String connectionStatus = 'Disconnected';

  /// Last error, if any.
  String? lastError;

  bool get connected => _connected;
  bool get enabled => _enabled;
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

  /// Update the coordinator URL and reconnect.
  void setServerUrl(String url) {
    _serverUrl = url;
    if (_enabled) {
      disconnect();
      connect();
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

  /// Connect to the coordinator server.
  void connect() {
    if (_channel != null) return;
    if (!_enabled) return;

    connectionStatus = 'Connecting…';
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

      // Register — connection is confirmed when stream starts delivering
      _send({
        'type': 'register',
        'device_id': _deviceId,
        'capabilities': ComputeJobType.values.map((e) => e.name).toList(),
      });

      // Mark connected after registering (stream listener is active)
      _connected = true;
      _reconnectAttempts = 0;
      connectionStatus = 'Connected to $_serverUrl';
      lastError = null;
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
        debugPrint('CoordinatorService: draining ${_offlineQueue.length} queued messages');
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

  /// Disconnect from the coordinator.
  void disconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _messageSub?.cancel();
    _messageSub = null;
    _resultSub?.cancel();
    _resultSub = null;

    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    _connected = false;
    connectionStatus = _enabled ? 'Disconnected (will retry)' : 'Disconnected';
    onStateChanged?.call();
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;

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

    if (_enabled) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    if (!_enabled) return;

    _reconnectAttempts++;
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
    disconnect();
    _compute.dispose();
  }
}
