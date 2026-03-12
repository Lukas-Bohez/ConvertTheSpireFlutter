import 'dart:async';

import 'cast_service.dart';
import 'chromecast_service.dart';
import 'dlna_service.dart';

/// Merges Chromecast and DLNA device discovery into a single service.
class UnifiedCastService extends CastService {
  final ChromecastCastService _chromecast = ChromecastCastService();
  final DlnaCastService _dlna = DlnaCastService();

  CastService? _activeCaster;

  UnifiedCastService() {
    _chromecast.addListener(_onChildChanged);
    _dlna.addListener(_onChildChanged);
  }

  void _onChildChanged() => notifyListeners();

  @override
  List<CastDevice> get discoveredDevices => [
        ..._chromecast.discoveredDevices,
        ..._dlna.discoveredDevices,
      ];

  @override
  CastPlaybackState get playbackState =>
      _activeCaster?.playbackState ?? CastPlaybackState.idle;

  @override
  CastDevice? get activeDevice => _activeCaster?.activeDevice;

  @override
  String? get activeUrl => _activeCaster?.activeUrl;

  @override
  Future<void> startDiscovery() async {
    await Future.wait([
      _chromecast.startDiscovery(),
      _dlna.startDiscovery(),
    ]);
  }

  @override
  Future<void> stopDiscovery() async {
    await _chromecast.stopDiscovery();
    await _dlna.stopDiscovery();
  }

  @override
  Future<void> castUrl(CastDevice device, String videoUrl,
      {String? title}) async {
    if (device.type == CastDeviceType.chromecast) {
      _activeCaster = _chromecast;
      await _chromecast.castUrl(device, videoUrl, title: title);
    } else {
      _activeCaster = _dlna;
      await _dlna.castUrl(device, videoUrl, title: title);
    }
  }

  @override
  Future<void> pause() async => _activeCaster?.pause();

  @override
  Future<void> resume() async => _activeCaster?.resume();

  @override
  Future<void> stop() async {
    await _activeCaster?.stop();
    _activeCaster = null;
  }

  @override
  Future<void> seek(Duration position) async =>
      _activeCaster?.seek(position);

  @override
  void dispose() {
    _chromecast.removeListener(_onChildChanged);
    _dlna.removeListener(_onChildChanged);
    _chromecast.dispose();
    _dlna.dispose();
    super.dispose();
  }
}
