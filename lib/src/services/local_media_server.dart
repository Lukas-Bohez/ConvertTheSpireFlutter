import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mime/mime.dart';

import 'media_range.dart';

/// A lightweight local HTTP server that serves media files to DLNA renderers
/// on the local network.
///
/// Uses raw dart:io HttpServer (no shelf dependency needed for simple file
/// serving).  Binds to all interfaces so any device on the LAN can fetch
/// the file.
class LocalMediaServer {
  HttpServer? _server;
  String? _servingPath;
  String? _servingMime;

  /// The port the server is currently listening on, or null if stopped.
  int? get port => _server?.port;

  /// Whether the server is running.
  bool get isRunning => _server != null;

  /// Start serving a single media file.
  ///
  /// Returns the URL that DLNA devices should use to access the file.
  /// [localIp] is this device's IP on the local network (e.g. `192.168.1.100`).
  ///
  /// If the server is already running, it replaces the file being served.
  Future<String> serve({
    required String filePath,
    required String localIp,
    int preferredPort = 0,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    _servingPath = filePath;
    _servingMime = lookupMimeType(filePath) ?? 'application/octet-stream';

    // If already running, just update the file path - keep the same port
    final existing = _server;
    if (existing != null) {
      final url = 'http://$localIp:${existing.port}/media';
      debugPrint('LocalMediaServer: updated file → $filePath  ($url)');
      return url;
    }

    // Start fresh
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      preferredPort,
      shared: true,
    );
    _server = server;

    final url = 'http://$localIp:${server.port}/media';
    debugPrint('LocalMediaServer: listening on $url  (serving $filePath)');

    server.listen((request) async {
      try {
        if (request.uri.path == '/media' && _servingPath != null) {
          await _handleMediaRequest(request);
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not found');
          await request.response.close();
        }
      } catch (e, st) {
        debugPrint('LocalMediaServer: request handler error: $e');
        debugPrint('$st');
        // Try to close the response if possible.
        try {
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write('Server error');
          } catch (_) {}
          await request.response.close();
        } catch (_) {}
      }
    }, onError: (e, st) {
      debugPrint('LocalMediaServer: listen stream error: $e');
      debugPrint('$st');
    });

    return url;
  }

  /// Handle a GET or HEAD request for the media file.
  ///
  /// Range support is what lets a TV seek. The logic lives in media_range.dart
  /// now, shared with the Watch Together host stream; this copy did no
  /// clamping, so a range past the end of the file was read as-is (issue #7).
  Future<void> _handleMediaRequest(HttpRequest request) async {
    try {
      final mime = _servingMime ?? 'application/octet-stream';
      await serveFileWithRanges(
        request,
        File(_servingPath!),
        contentType: mime,
        extraHeaders: {
          'Connection': 'keep-alive',
          'transferMode.dlna.org': 'Streaming',
          'contentFeatures.dlna.org': _dlnaContentFeatures(mime),
        },
      );
    } catch (e, st) {
      debugPrint('LocalMediaServer: request processing failed: $e');
      debugPrint('$st');
      try {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write('Server error');
        } catch (_) {}
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Stop the server and release the port.
  Future<void> stop() async {
    final server = _server;
    if (server != null) {
      debugPrint('LocalMediaServer: stopping');
      _server = null;
      _servingPath = null;
      _servingMime = null;
      await server.close(force: true);
    }
  }

  /// Build a basic DLNA content features string.
  static String _dlnaContentFeatures(String mime) {
    // DLNA.ORG_PN profile name varies by format; fallback to wildcard
    final pn = _dlnaProfile(mime);
    return '${pn}DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000';
  }

  static String _dlnaProfile(String mime) {
    if (mime.contains('mp4') || mime.contains('video/mp4')) {
      return 'DLNA.ORG_PN=AVC_MP4_BL_CIF15_AAC_520;';
    }
    if (mime.contains('mpeg') || mime.contains('audio/mpeg')) {
      return 'DLNA.ORG_PN=MP3;';
    }
    if (mime.contains('audio/mp4') || mime.contains('m4a')) {
      return 'DLNA.ORG_PN=AAC_ISO_320;';
    }
    return '';
  }

  /// Get the local IP address of this device on the LAN.
  ///
  /// Iterates through network interfaces and returns the first non-loopback
  /// IPv4 address.
  static Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (e) {
      debugPrint('Failed to determine local IP: $e');
    }
    return null;
  }
}
