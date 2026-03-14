import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mime/mime.dart';

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

    // If already running, just update the file path — keep the same port
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
  Future<void> _handleMediaRequest(HttpRequest request) async {
    try {
      final file = File(_servingPath!);
      if (!await file.exists()) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('File no longer available');
        await request.response.close();
        return;
      }

      final length = await file.length();
      final mime = _servingMime ?? 'application/octet-stream';

      // Set headers that DLNA renderers expect
      request.response.headers
        ..contentType = ContentType.parse(mime)
        ..contentLength = length
        ..set('Accept-Ranges', 'bytes')
        ..set('Connection', 'keep-alive')
        ..set('transferMode.dlna.org', 'Streaming')
        ..set('contentFeatures.dlna.org', _dlnaContentFeatures(mime));

      // Handle Range requests (many TVs use these for seeking)
      final rangeHeader = request.headers.value('range');
      if (rangeHeader != null && request.method == 'GET') {
        final rangeMatch = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
        if (rangeMatch != null) {
          final start = int.parse(rangeMatch.group(1) ?? '0');
          final endStr = rangeMatch.group(2) ?? '';
          final end = endStr.isNotEmpty ? int.parse(endStr) : length - 1;
          final rangeLength = end - start + 1;

          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set('Content-Range', 'bytes $start-$end/$length')
            ..headers.contentLength = rangeLength;

          try {
            await file.openRead(start, end + 1).pipe(request.response);
          } catch (e, st) {
            debugPrint('LocalMediaServer: pipe error: $e');
            debugPrint('$st');
            try {
              await request.response.close();
            } catch (_) {}
          }
          return;
        }
      }

      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }

      // Full file
      try {
        await file.openRead().pipe(request.response);
      } catch (e, st) {
        debugPrint('LocalMediaServer: pipe error: $e');
        debugPrint('$st');
        try {
          await request.response.close();
        } catch (_) {}
      }
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
