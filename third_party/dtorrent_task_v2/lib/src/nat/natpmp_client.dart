import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';

/// Logger instance for NATPMPClient
final _log = Logger('NATPMPClient');

/// NAT-PMP (NAT Port Mapping Protocol) client for port forwarding
///
/// Implements NAT-PMP protocol (RFC 6886) for automatic port forwarding.
/// NAT-PMP is simpler than UPnP and is used by Apple routers.
class NATPMPClient {
  /// NAT-PMP server address (gateway IP)
  InternetAddress? _gatewayAddress;

  /// Flag to track if discovery was already attempted
  bool _discoveryAttempted = false;

  /// NAT-PMP server port (always 5351)
  static const int NATPMP_PORT = 5351;

  /// Request timeout
  final Duration timeout;

  NATPMPClient({this.timeout = const Duration(seconds: 5)});

  /// Discover NAT-PMP gateway (router)
  ///
  /// NAT-PMP gateway is typically the default gateway (router IP).
  /// This method attempts to discover it by trying common gateway IPs.
  /// Uses a shorter timeout per gateway test to avoid long delays.
  Future<InternetAddress?> discoverGateway() async {
    try {
      _log.info('Discovering NAT-PMP gateway...');

      // Use shorter timeout for discovery to avoid long delays
      final discoveryTimeout = Duration(
                milliseconds: timeout.inMilliseconds ~/ 2,
              ).inMilliseconds >
              0
          ? Duration(milliseconds: timeout.inMilliseconds ~/ 2)
          : const Duration(milliseconds: 500);

      // Try to get default gateway from network interfaces
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );

      // Limit number of interfaces to test to avoid long delays
      final maxInterfaces = 3;
      var interfaceCount = 0;

      for (var interface in interfaces) {
        if (interfaceCount >= maxInterfaces) break;
        for (var addr in interface.addresses) {
          // Try common gateway addresses (last octet = 1)
          final gatewayIP = _getGatewayIP(addr);
          if (gatewayIP != null) {
            if (await _testGateway(gatewayIP, timeout: discoveryTimeout)) {
              _gatewayAddress = gatewayIP;
              _log.info('NAT-PMP gateway found: $gatewayIP');
              return gatewayIP;
            }
          }
        }
        interfaceCount++;
      }

      // Fallback: try common gateway IPs (limit to 2 most common)
      final commonGateways = [
        '192.168.1.1',
        '192.168.0.1',
      ];

      for (var gwStr in commonGateways) {
        try {
          final gw = InternetAddress(gwStr);
          if (await _testGateway(gw, timeout: discoveryTimeout)) {
            _gatewayAddress = gw;
            _log.info('NAT-PMP gateway found: $gw');
            return gw;
          }
        } catch (e) {
          // Continue to next
        }
      }

      _log.warning('NAT-PMP gateway not found');
      return null;
    } catch (e, stackTrace) {
      _log.warning('NAT-PMP discovery failed', e, stackTrace);
      return null;
    }
  }

  /// Get gateway IP from interface address
  InternetAddress? _getGatewayIP(InternetAddress addr) {
    // Parse IP address string to get octets
    final addrStr = addr.address;
    final parts = addrStr.split('.');
    if (parts.length == 4) {
      try {
        // Set last octet to 1 (common gateway pattern)
        final gatewayParts = [
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
          1, // Last octet set to 1
        ];
        return InternetAddress.fromRawAddress(Uint8List.fromList(gatewayParts));
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Test if gateway supports NAT-PMP
  Future<bool> _testGateway(
    InternetAddress gateway, {
    Duration? timeout,
  }) async {
    try {
      // Use provided timeout or default client timeout
      final testTimeout = timeout ?? this.timeout;

      // Send public address request (version 0, opcode 0)
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      try {
        final request = ByteData(2);
        request.setUint8(0, 0); // Version
        request.setUint8(1, 0); // Opcode: Public IP Address Request

        socket.send(request.buffer.asUint8List(), gateway, NATPMP_PORT);

        // Wait for response
        final completer = Completer<bool>();
        Timer? timeoutTimer;
        StreamSubscription<RawSocketEvent>? subscription;

        subscription = socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram != null &&
                datagram.address == gateway &&
                datagram.port == NATPMP_PORT) {
              timeoutTimer?.cancel();
              subscription?.cancel();
              // Check response format
              if (datagram.data.length >= 12) {
                final response = ByteData.sublistView(datagram.data);
                final version = response.getUint8(0);
                final resultCode = response.getUint16(1, Endian.big);
                // Version 0 and result code 0 = success
                completer.complete(version == 0 && resultCode == 0);
              } else {
                completer.complete(false);
              }
            }
          }
        });

        timeoutTimer = Timer(testTimeout, () {
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        });

        return await completer.future;
      } finally {
        socket.close();
      }
    } catch (e) {
      return false;
    }
  }

  /// Add port mapping (forward port)
  ///
  /// [externalPort] - External port to forward
  /// [internalPort] - Internal port (usually same as external)
  /// [protocol] - 1 for TCP, 2 for UDP
  /// [leaseDuration] - Lease duration in seconds (0 = permanent, max 65535)
  Future<bool> addPortMapping({
    required int externalPort,
    required int internalPort,
    int protocol = 1, // 1 = TCP, 2 = UDP
    int leaseDuration = 3600, // 1 hour default
  }) async {
    try {
      // Discover gateway if not already discovered and not already attempted
      if (_gatewayAddress == null && !_discoveryAttempted) {
        _discoveryAttempted = true;
        _gatewayAddress = await discoverGateway();
        if (_gatewayAddress == null) {
          _log.warning('Cannot add port mapping: gateway not found');
          return false;
        }
      } else if (_gatewayAddress == null) {
        // Already attempted discovery and failed, don't try again
        _log.warning(
            'Cannot add port mapping: gateway not found (discovery already attempted)');
        return false;
      }

      _log.info(
          'Adding NAT-PMP port mapping: $externalPort -> $internalPort (protocol: $protocol)');

      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      try {
        // Build NAT-PMP request (version 0, opcode 1 for TCP or 2 for UDP)
        final request = ByteData(12);
        request.setUint8(0, 0); // Version
        request.setUint8(1, protocol); // Opcode: 1 = TCP, 2 = UDP
        request.setUint16(2, 0, Endian.big); // Reserved
        request.setUint16(4, internalPort, Endian.big); // Internal port
        request.setUint16(
            6, externalPort, Endian.big); // Requested external port
        request.setUint32(8, leaseDuration, Endian.big); // Lease duration

        socket.send(
          request.buffer.asUint8List(),
          _gatewayAddress!,
          NATPMP_PORT,
        );

        // Wait for response
        final completer = Completer<bool>();
        Timer? timeoutTimer;
        StreamSubscription<RawSocketEvent>? subscription;

        subscription = socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram != null &&
                datagram.address == _gatewayAddress &&
                datagram.port == NATPMP_PORT) {
              timeoutTimer?.cancel();
              subscription?.cancel();

              if (datagram.data.length >= 16) {
                final response = ByteData.sublistView(datagram.data);
                final version = response.getUint8(0);
                final resultCode = response.getUint16(1, Endian.big);

                if (version == 0 && resultCode == 0) {
                  final mappedExternalPort = response.getUint16(8, Endian.big);
                  final mappedInternalPort = response.getUint16(10, Endian.big);
                  final actualLeaseDuration =
                      response.getUint32(12, Endian.big);

                  _log.info(
                      'Port mapping added: $mappedExternalPort -> $mappedInternalPort (lease: ${actualLeaseDuration}s)');
                  completer.complete(true);
                } else {
                  _log.warning('NAT-PMP error: result code $resultCode');
                  completer.complete(false);
                }
              } else {
                completer.complete(false);
              }
            }
          }
        });

        timeoutTimer = Timer(timeout, () {
          subscription?.cancel();
          if (!completer.isCompleted) {
            _log.warning('NAT-PMP request timeout');
            completer.complete(false);
          }
        });

        return await completer.future;
      } finally {
        socket.close();
      }
    } catch (e, stackTrace) {
      _log.warning('Error adding NAT-PMP port mapping', e, stackTrace);
      return false;
    }
  }

  /// Delete port mapping (remove port forward)
  ///
  /// NAT-PMP doesn't have explicit delete - ports are removed when lease expires.
  /// However, we can set lease duration to 0 to immediately remove it.
  Future<bool> deletePortMapping({
    required int externalPort,
    int protocol = 1, // 1 = TCP, 2 = UDP
  }) async {
    // Set lease duration to 0 to remove mapping
    return await addPortMapping(
      externalPort: externalPort,
      internalPort: externalPort,
      protocol: protocol,
      leaseDuration: 0,
    );
  }

  /// Get external IP address
  Future<InternetAddress?> getExternalIP() async {
    try {
      if (_gatewayAddress == null) {
        _gatewayAddress = await discoverGateway();
        if (_gatewayAddress == null) {
          return null;
        }
      }

      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      try {
        // Request public IP (version 0, opcode 0)
        final request = ByteData(2);
        request.setUint8(0, 0); // Version
        request.setUint8(1, 0); // Opcode: Public IP Address Request

        socket.send(
          request.buffer.asUint8List(),
          _gatewayAddress!,
          NATPMP_PORT,
        );

        // Wait for response
        final completer = Completer<InternetAddress?>();
        Timer? timeoutTimer;
        StreamSubscription<RawSocketEvent>? subscription;

        subscription = socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram != null &&
                datagram.address == _gatewayAddress &&
                datagram.port == NATPMP_PORT) {
              timeoutTimer?.cancel();
              subscription?.cancel();

              if (datagram.data.length >= 12) {
                final response = ByteData.sublistView(datagram.data);
                final version = response.getUint8(0);
                final resultCode = response.getUint16(1, Endian.big);

                if (version == 0 && resultCode == 0) {
                  // Extract IP address (bytes 8-11)
                  final ipBytes = datagram.data.sublist(8, 12);
                  final ip = InternetAddress.fromRawAddress(ipBytes);
                  _log.info('External IP: $ip');
                  completer.complete(ip);
                } else {
                  completer.complete(null);
                }
              } else {
                completer.complete(null);
              }
            }
          }
        });

        timeoutTimer = Timer(timeout, () {
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        });

        return await completer.future;
      } finally {
        socket.close();
      }
    } catch (e, stackTrace) {
      _log.warning('Error getting external IP via NAT-PMP', e, stackTrace);
      return null;
    }
  }
}
