import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'dlna_discovery_service.dart';

/// Sends UPnP/DLNA control commands (SOAP actions) to a media renderer.
///
/// Implements the AVTransport:1 actions needed to play, pause, stop, and
/// seek media on a DLNA TV or speaker.
class DlnaControlService {
  static const _avTransportUrn =
      'urn:schemas-upnp-org:service:AVTransport:1';

  /// Set the media URI on the renderer and start playback.
  ///
  /// [device]   – target DLNA device (from discovery).
  /// [mediaUrl] – HTTP URL of the media file (served by our local server).
  /// [title]    – display title shown on the TV's OSD.
  /// [mimeType] – MIME type of the media (e.g. `audio/mpeg`, `video/mp4`).
  Future<void> playMedia({
    required DlnaDevice device,
    required String mediaUrl,
    String title = 'Convert the Spire',
    String mimeType = 'video/mp4',
  }) async {
    // Step 1: Stop any currently playing media (ignore errors)
    try {
      await stop(device);
    } catch (_) {}

    // Step 2: Set the transport URI
    await setAVTransportURI(
      device: device,
      mediaUrl: mediaUrl,
      title: title,
      mimeType: mimeType,
    );

    // Small delay to let the TV process the URI
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 3: Send Play command
    await play(device);
  }

  /// Send SetAVTransportURI to load a media URL onto the renderer.
  Future<void> setAVTransportURI({
    required DlnaDevice device,
    required String mediaUrl,
    String title = 'Convert the Spire',
    String mimeType = 'video/mp4',
  }) async {
    final escapedUrl = _xmlEscape(mediaUrl);
    final escapedTitle = _xmlEscape(title);

    final didlMetadata = _xmlEscape(
      '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
      '<item id="0" parentID="-1" restricted="1">'
      '<dc:title>$escapedTitle</dc:title>'
      '<upnp:class>object.item.videoItem</upnp:class>'
      '<res protocolInfo="http-get:*:$mimeType:*">$escapedUrl</res>'
      '</item>'
      '</DIDL-Lite>',
    );

    final soapBody = '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:SetAVTransportURI xmlns:u="$_avTransportUrn">'
        '<InstanceID>0</InstanceID>'
        '<CurrentURI>$escapedUrl</CurrentURI>'
        '<CurrentURIMetaData>$didlMetadata</CurrentURIMetaData>'
        '</u:SetAVTransportURI>'
        '</s:Body>'
        '</s:Envelope>';

    await _sendSoapAction(
      device.controlUrl,
      '$_avTransportUrn#SetAVTransportURI',
      soapBody,
    );
  }

  /// Send Play action.
  Future<void> play(DlnaDevice device) async {
    final soapBody = '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:Play xmlns:u="$_avTransportUrn">'
        '<InstanceID>0</InstanceID>'
        '<Speed>1</Speed>'
        '</u:Play>'
        '</s:Body>'
        '</s:Envelope>';

    await _sendSoapAction(
      device.controlUrl,
      '$_avTransportUrn#Play',
      soapBody,
    );
  }

  /// Send Pause action.
  Future<void> pause(DlnaDevice device) async {
    final soapBody = '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:Pause xmlns:u="$_avTransportUrn">'
        '<InstanceID>0</InstanceID>'
        '</u:Pause>'
        '</s:Body>'
        '</s:Envelope>';

    await _sendSoapAction(
      device.controlUrl,
      '$_avTransportUrn#Pause',
      soapBody,
    );
  }

  /// Send Stop action.
  Future<void> stop(DlnaDevice device) async {
    final soapBody = '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:Stop xmlns:u="$_avTransportUrn">'
        '<InstanceID>0</InstanceID>'
        '</u:Stop>'
        '</s:Body>'
        '</s:Envelope>';

    await _sendSoapAction(
      device.controlUrl,
      '$_avTransportUrn#Stop',
      soapBody,
    );
  }

  /// Send Seek action (position format: HH:MM:SS).
  Future<void> seek(DlnaDevice device, Duration position) async {
    final h = position.inHours.toString().padLeft(2, '0');
    final m = (position.inMinutes % 60).toString().padLeft(2, '0');
    final s = (position.inSeconds % 60).toString().padLeft(2, '0');
    final target = '$h:$m:$s';

    final soapBody = '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:Seek xmlns:u="$_avTransportUrn">'
        '<InstanceID>0</InstanceID>'
        '<Unit>REL_TIME</Unit>'
        '<Target>$target</Target>'
        '</u:Seek>'
        '</s:Body>'
        '</s:Envelope>';

    await _sendSoapAction(
      device.controlUrl,
      '$_avTransportUrn#Seek',
      soapBody,
    );
  }

  /// Get current transport state (PLAYING, PAUSED, STOPPED, etc.).
  Future<String> getTransportState(DlnaDevice device) async {
    final soapBody = '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:GetTransportInfo xmlns:u="$_avTransportUrn">'
        '<InstanceID>0</InstanceID>'
        '</u:GetTransportInfo>'
        '</s:Body>'
        '</s:Envelope>';

    final responseBody = await _sendSoapAction(
      device.controlUrl,
      '$_avTransportUrn#GetTransportInfo',
      soapBody,
    );

    final match = RegExp(r'<CurrentTransportState>(.*?)</CurrentTransportState>')
        .firstMatch(responseBody);
    return match?.group(1) ?? 'UNKNOWN';
  }

  /// Send a SOAP action to the device's control URL.
  Future<String> _sendSoapAction(
    String controlUrl,
    String soapAction,
    String body,
  ) async {
    debugPrint('DLNA SOAP → $controlUrl  action=$soapAction');

    try {
      final response = await http
          .post(
            Uri.parse(controlUrl),
            headers: {
              'Content-Type': 'text/xml; charset="utf-8"',
              'SOAPAction': '"$soapAction"',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('DLNA SOAP ← ${response.statusCode}');

      if (response.statusCode >= 400) {
        final errorBody = response.body;
        // Try to extract UPnP error description
        final errorMatch = RegExp(r'<errorDescription>(.*?)</errorDescription>')
            .firstMatch(errorBody);
        final errorDesc = errorMatch?.group(1) ?? 'HTTP ${response.statusCode}';
        throw Exception('DLNA command failed: $errorDesc');
      }

      return response.body;
    } on TimeoutException {
      throw Exception(
        'Device did not respond. Ensure the TV is on and connected to the same network.',
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to communicate with device: $e');
    }
  }

  /// Escape XML special characters.
  static String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
