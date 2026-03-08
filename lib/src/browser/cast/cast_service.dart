import 'dart:async';

import 'package:flutter/foundation.dart';

/// Type of cast-capable device.
enum CastDeviceType { chromecast, dlna }

/// Playback state reported by a cast device.
enum CastPlaybackState { idle, buffering, playing, paused, stopped, unknown }

/// A discovered device that can receive media.
class CastDevice {
  final String id;
  final String name;
  final CastDeviceType type;

  /// Opaque data used by the concrete service (e.g. DLNA controlUrl).
  final dynamic nativeHandle;

  const CastDevice({
    required this.id,
    required this.name,
    required this.type,
    this.nativeHandle,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CastDevice && id == other.id && type == other.type;

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String toString() => 'CastDevice($name, $type)';
}

/// Unified interface for casting media to TV devices.
abstract class CastService extends ChangeNotifier {
  List<CastDevice> get discoveredDevices;
  CastPlaybackState get playbackState;
  CastDevice? get activeDevice;
  String? get activeUrl;

  Future<void> startDiscovery();
  Future<void> stopDiscovery();

  Future<void> castUrl(CastDevice device, String videoUrl, {String? title});
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);

  @override
  void dispose();
}
