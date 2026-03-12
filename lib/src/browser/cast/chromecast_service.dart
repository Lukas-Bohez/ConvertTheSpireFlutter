import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cast_service.dart';

/// Chromecast discovery stub.
///
/// The upstream `cast` pub package (2.1.0) is currently incompatible with
/// bonsoir 6.x (missing `BonsoirDiscovery.ready` getter). Chromecast support
/// is disabled until the package is fixed.  DLNA casting remains fully
/// functional via [DlnaCastService].
class ChromecastCastService extends CastService {
  @override
  List<CastDevice> get discoveredDevices => const [];
  @override
  CastPlaybackState get playbackState => CastPlaybackState.idle;
  @override
  CastDevice? get activeDevice => null;
  @override
  String? get activeUrl => null;

  @override
  Future<void> startDiscovery() async {
    if (kDebugMode) {
      debugPrint('Chromecast discovery disabled — cast package incompatible');
    }
  }

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<void> castUrl(CastDevice device, String videoUrl,
      {String? title}) async {
    throw UnsupportedError('Chromecast casting is not yet available');
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}

  @override
  void dispose() {
    super.dispose();
  }
}
