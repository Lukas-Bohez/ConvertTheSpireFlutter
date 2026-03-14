import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';

/// The type of discovered device for icon display.
enum DiscoveredDeviceType {
  dlnaRenderer,
  googleCast,
  airplay,
  manual;

  IconData get icon {
    switch (this) {
      case DiscoveredDeviceType.dlnaRenderer:
        return Icons.speaker;
      case DiscoveredDeviceType.googleCast:
        return Icons.cast;
      case DiscoveredDeviceType.airplay:
        return Icons.airplay;
      case DiscoveredDeviceType.manual:
        return Icons.settings_input_antenna;
    }
  }
}

/// A discovered DLNA/UPnP media renderer on the local network.
class DlnaDevice {
  final String name;
  final String type;
  final String location; // URL to the device description XML
  final String controlUrl; // AVTransport control URL
  final String udn; // Unique Device Name
  final InternetAddress address;
  final bool isPanasonicViera;
  final DiscoveredDeviceType deviceType;

  const DlnaDevice({
    required this.name,
    required this.type,
    required this.location,
    required this.controlUrl,
    required this.udn,
    required this.address,
    this.isPanasonicViera = false,
    this.deviceType = DiscoveredDeviceType.dlnaRenderer,
  });

  @override
  String toString() => 'DlnaDevice($name @ ${address.address})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DlnaDevice && udn == other.udn;

  @override
  int get hashCode => udn.hashCode;
}

/// Discovers DLNA/UPnP media renderers on the local network using SSDP
/// (Simple Service Discovery Protocol).
///
/// Sends an M-SEARCH multicast to 239.255.255.250:1900 and parses responses
/// to identify devices that implement the AVTransport service.
class DlnaDiscoveryService {
  static const _multicastAddress = '239.255.255.250';
  static const _multicastPort = 1900;
  static const _searchTarget = 'urn:schemas-upnp-org:service:AVTransport:1';

  /// Scan for DLNA renderers and Cast/AirPlay devices. Returns discovered
  /// devices sorted with Panasonic Viera TVs first, then by name.
  ///
  /// Runs SSDP and mDNS discovery in parallel and merges the results.
  /// [timeout] controls how long we listen for responses.
  Future<List<DlnaDevice>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final results = await Future.wait([
      _discoverViaSsdp(timeout: timeout),
      _discoverViaMdns(timeout: timeout),
    ]);

    final devices = <String, DlnaDevice>{}; // keyed by udn for dedup
    for (final list in results) {
      for (final d in list) {
        devices.putIfAbsent(d.udn, () => d);
      }
    }

    final sorted = devices.values.toList()
      ..sort((a, b) {
        if (a.isPanasonicViera && !b.isPanasonicViera) return -1;
        if (!a.isPanasonicViera && b.isPanasonicViera) return 1;
        return a.name.compareTo(b.name);
      });
    return sorted;
  }

  /// SSDP multicast discovery for DLNA/UPnP renderers.
  Future<List<DlnaDevice>> _discoverViaSsdp({
    required Duration timeout,
  }) async {
    final devices = <DlnaDevice>{};
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? timer;
    final completer = Completer<List<DlnaDevice>>();
    final pendingParses = <Future<DlnaDevice?>>[];

    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );

      // Build M-SEARCH message
      final message = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: $_multicastAddress:$_multicastPort\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: ${timeout.inSeconds}\r\n'
          'ST: $_searchTarget\r\n'
          '\r\n';

      // Send the multicast
      socket.send(
        utf8.encode(message),
        InternetAddress(_multicastAddress),
        _multicastPort,
      );

      // Also search for generic media renderers
      final message2 = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: $_multicastAddress:$_multicastPort\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: ${timeout.inSeconds}\r\n'
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
          '\r\n';
      socket.send(
        utf8.encode(message2),
        InternetAddress(_multicastAddress),
        _multicastPort,
      );

      subscription = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          try {
            final datagram = socket?.receive();
            if (datagram == null) return;
            final response = utf8.decode(datagram.data, allowMalformed: true);
            final future = _parseResponse(response, datagram.address).catchError((e) {
              debugPrint('DLNA: failed to parse response: $e');
              return null;
            });
            pendingParses.add(future);
          } catch (e) {
            debugPrint('DLNA SSDP read handler error: $e');
          }
        }
      }, onError: (e) {
        debugPrint('DLNA SSDP subscription error: $e');
      });

      // Wait for timeout, then await all pending parse operations
      timer = Timer(timeout, () async {
        try {
          await subscription?.cancel();
        } catch (_) {}
        try {
          socket?.close();
        } catch (_) {}

        final results = await Future.wait(pendingParses);
        for (final device in results) {
          if (device != null) devices.add(device);
        }
        if (!completer.isCompleted) {
          completer.complete(devices.toList());
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('DLNA SSDP discovery error: $e');
      try {
        timer?.cancel();
      } catch (_) {}
      try {
        await subscription?.cancel();
      } catch (_) {}
      try {
        socket?.close();
      } catch (_) {}
      return devices.toList();
    }
  }

  /// mDNS discovery for Google Cast and AirPlay devices.
  Future<List<DlnaDevice>> _discoverViaMdns({
    required Duration timeout,
  }) async {
    if (kIsWeb) return [];
    // mDNS APIs used here rely on socket options that are not supported on
    // Windows in this environment and cause O/S errors. Disable mDNS on
    // Windows to avoid socket option failures (use SSDP only).
    try {
      if (Platform.isWindows) {
        debugPrint('mDNS discovery disabled on Windows');
        return [];
      }
    } catch (_) {}

    final devices = <DlnaDevice>[];
    MDnsClient? client;

    try {
      client = MDnsClient();
      await client.start();

      const services = {
        '_googlecast._tcp': DiscoveredDeviceType.googleCast,
        '_airplay._tcp': DiscoveredDeviceType.airplay,
      };

      for (final entry in services.entries) {
        final serviceType = entry.key;
        final deviceType = entry.value;

        await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(serviceType),
          timeout: timeout,
        )) {
          // Resolve SRV for host + port
          await for (final srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
            timeout: const Duration(seconds: 3),
          )) {
            // Resolve A record for IP
            await for (final ip in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
              timeout: const Duration(seconds: 3),
            )) {
              // Try to get friendly name from TXT record
              String friendlyName = ptr.domainName
                  .replaceAll('.$serviceType', '')
                  .replaceAll(RegExp(r'\.$'), '');

              try {
                await for (final txt in client.lookup<TxtResourceRecord>(
                  ResourceRecordQuery.text(ptr.domainName),
                  timeout: const Duration(seconds: 2),
                )) {
                  final fnEntry = txt.text
                      .split('\n')
                      .where((l) => l.startsWith('fn='))
                      .firstOrNull;
                  if (fnEntry != null) {
                    friendlyName = fnEntry.substring(3);
                  }
                  break; // only need first TXT
                }
              } catch (_) {}

              devices.add(DlnaDevice(
                name: friendlyName,
                type: serviceType,
                location: 'http://${ip.address.address}:${srv.port}/',
                controlUrl: 'http://${ip.address.address}:${srv.port}/',
                udn: 'mdns-${ip.address.address}:${srv.port}',
                address: ip.address,
                deviceType: deviceType,
              ));
              break; // first IP is enough
            }
            break; // first SRV is enough
          }
        }
      }
    } catch (e) {
      debugPrint('mDNS discovery error: $e');
    } finally {
      client?.stop();
    }

    return devices;
  }

  /// Create a DlnaDevice from a manually entered IP address.
  ///
  /// Attempts to fetch the device description XML from common DLNA ports.
  Future<DlnaDevice?> discoverByIp(String ip) async {
    final commonPorts = [
      8060,
      55000,
      49152,
      49153,
      7676,
      8008,
      8443,
      1400,
      9197
    ];
    final address = InternetAddress(ip);

    for (final port in commonPorts) {
      try {
        final locationUrl = 'http://$ip:$port/dmr.xml';
        final device = await _fetchDeviceDescription(locationUrl, address);
        if (device != null) return device;
      } catch (_) {}

      try {
        final locationUrl = 'http://$ip:$port/description.xml';
        final device = await _fetchDeviceDescription(locationUrl, address);
        if (device != null) return device;
      } catch (_) {}

      try {
        final locationUrl = 'http://$ip:$port/DeviceDescription.xml';
        final device = await _fetchDeviceDescription(locationUrl, address);
        if (device != null) return device;
      } catch (_) {}
    }

    // Last resort: create a device with assumed Panasonic-style control URL
    return DlnaDevice(
      name: 'Device at $ip',
      type: 'Unknown DLNA Renderer',
      location: 'http://$ip:55000/dmr.xml',
      controlUrl: 'http://$ip:55000/dmr/control_0',
      udn: 'manual-$ip',
      address: address,
      isPanasonicViera: false,
      deviceType: DiscoveredDeviceType.manual,
    );
  }

  /// Parse an SSDP response to extract the LOCATION header, then fetch
  /// the device description XML to build a [DlnaDevice].
  Future<DlnaDevice?> _parseResponse(
    String response,
    InternetAddress address,
  ) async {
    // Extract LOCATION header
    final locationMatch = RegExp(
      r'LOCATION:\s*(.+)',
      caseSensitive: false,
    ).firstMatch(response);
    if (locationMatch == null) return null;

    final location = locationMatch.group(1)!.trim();
    return _fetchDeviceDescription(location, address);
  }

  /// Fetch and parse the UPnP device description XML.
  Future<DlnaDevice?> _fetchDeviceDescription(
    String location,
    InternetAddress address,
  ) async {
    try {
      final resp = await http
          .get(Uri.parse(location))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;

      final xml = resp.body;

      // Extract device name
      final nameMatch =
          RegExp(r'<friendlyName>(.*?)</friendlyName>').firstMatch(xml);
      final name = nameMatch?.group(1) ?? 'Unknown Device';

      // Extract device type
      final typeMatch =
          RegExp(r'<deviceType>(.*?)</deviceType>').firstMatch(xml);
      final type = typeMatch?.group(1) ?? '';

      // Extract UDN
      final udnMatch = RegExp(r'<UDN>(.*?)</UDN>').firstMatch(xml);
      final udn = udnMatch?.group(1) ?? location;

      // Extract manufacturer for Panasonic detection
      final mfgMatch =
          RegExp(r'<manufacturer>(.*?)</manufacturer>').firstMatch(xml);
      final manufacturer = mfgMatch?.group(1)?.toLowerCase() ?? '';
      final isPanasonic = manufacturer.contains('panasonic');

      // Find the AVTransport control URL
      final controlUrl = _extractAVTransportControlUrl(xml, location);
      if (controlUrl == null) return null;

      return DlnaDevice(
        name: name,
        type: type,
        location: location,
        controlUrl: controlUrl,
        udn: udn,
        address: address,
        isPanasonicViera: isPanasonic,
      );
    } catch (e) {
      debugPrint('DLNA: failed to fetch device description from $location: $e');
      return null;
    }
  }

  /// Parse the device description XML to find the AVTransport service
  /// control URL.  Returns a fully qualified URL.
  String? _extractAVTransportControlUrl(String xml, String baseLocation) {
    // Look for the AVTransport service block
    final avTransportPattern = RegExp(
      r'<service>.*?<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>.*?<controlURL>(.*?)</controlURL>.*?</service>',
      dotAll: true,
    );
    final match = avTransportPattern.firstMatch(xml);
    if (match == null) {
      // Fallback: try to find any controlURL
      final fallback =
          RegExp(r'<controlURL>(.*?)</controlURL>').firstMatch(xml);
      if (fallback == null) return null;
      return _resolveUrl(baseLocation, fallback.group(1)!);
    }
    return _resolveUrl(baseLocation, match.group(1)!);
  }

  /// Resolve a possibly-relative control URL against the device's base
  /// location URL.
  String _resolveUrl(String baseLocation, String controlPath) {
    if (controlPath.startsWith('http://') ||
        controlPath.startsWith('https://')) {
      return controlPath;
    }
    final baseUri = Uri.parse(baseLocation);
    final base = '${baseUri.scheme}://${baseUri.host}:${baseUri.port}';
    final path = controlPath.startsWith('/') ? controlPath : '/$controlPath';
    return '$base$path';
  }
}
