import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/dlna_control_service.dart';
import '../../services/dlna_discovery_service.dart';
import 'cast_service.dart';

/// DLNA casting implementation using the app's existing DLNA discovery/control.
class DlnaCastService extends CastService {
  final DlnaDiscoveryService _discovery = DlnaDiscoveryService();
  final DlnaControlService _control = DlnaControlService();

  List<CastDevice> _devices = [];
  CastPlaybackState _state = CastPlaybackState.idle;
  CastDevice? _activeDevice;
  String? _activeUrl;
  Timer? _pollTimer;

  @override
  List<CastDevice> get discoveredDevices => List.unmodifiable(_devices);
  @override
  CastPlaybackState get playbackState => _state;
  @override
  CastDevice? get activeDevice => _activeDevice;
  @override
  String? get activeUrl => _activeUrl;

  @override
  Future<void> startDiscovery() async {
    try {
      final dlnaDevices =
          await _discovery.discover(timeout: const Duration(seconds: 5));
      _devices = dlnaDevices
          .map((d) => CastDevice(
                id: d.udn.isNotEmpty ? d.udn : d.controlUrl,
                name: d.name,
                type: CastDeviceType.dlna,
                nativeHandle: d,
              ))
          .toList();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('DLNA discovery error: $e');
    }
  }

  @override
  Future<void> stopDiscovery() async {
    // SSDP discovery is one-shot; nothing to stop.
  }

  @override
  Future<void> castUrl(CastDevice device, String videoUrl,
      {String? title}) async {
    final dlnaDevice = device.nativeHandle as DlnaDevice;
    await _control.playMedia(
      device: dlnaDevice,
      mediaUrl: videoUrl,
      title: title ?? 'Video',
    );
    _activeDevice = device;
    _activeUrl = videoUrl;
    _state = CastPlaybackState.playing;
    notifyListeners();
    _startPolling(dlnaDevice);
  }

  @override
  Future<void> pause() async {
    if (_activeDevice == null) return;
    final d = _activeDevice!.nativeHandle as DlnaDevice;
    await _control.pause(d);
    _state = CastPlaybackState.paused;
    notifyListeners();
  }

  @override
  Future<void> resume() async {
    if (_activeDevice == null) return;
    final d = _activeDevice!.nativeHandle as DlnaDevice;
    await _control.play(d);
    _state = CastPlaybackState.playing;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _pollTimer?.cancel();
    if (_activeDevice != null) {
      final d = _activeDevice!.nativeHandle as DlnaDevice;
      try {
        await _control.stop(d);
      } catch (_) {}
    }
    _activeDevice = null;
    _activeUrl = null;
    _state = CastPlaybackState.idle;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_activeDevice == null) return;
    final d = _activeDevice!.nativeHandle as DlnaDevice;
    await _control.seek(d, position);
  }

  void _startPolling(DlnaDevice device) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final state = await _control.getTransportState(device);
        final newState = switch (state) {
          'PLAYING' => CastPlaybackState.playing,
          'PAUSED_PLAYBACK' => CastPlaybackState.paused,
          'STOPPED' => CastPlaybackState.stopped,
          'TRANSITIONING' => CastPlaybackState.buffering,
          _ => CastPlaybackState.unknown,
        };
        if (newState != _state) {
          _state = newState;
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
