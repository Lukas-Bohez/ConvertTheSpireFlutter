import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'proxy_config.dart';

var _log = Logger('Socks5Client');

/// SOCKS5 proxy client for peer connections
class Socks5Client {
  final ProxyConfig config;

  Socks5Client(this.config) {
    if (config.type != ProxyType.socks5) {
      throw ArgumentError('Socks5Client only supports SOCKS5 proxies');
    }
  }

  /// Connect to target through SOCKS5 proxy
  ///
  /// [targetAddress] - Target IP address
  /// [targetPort] - Target port
  /// [timeout] - Connection timeout
  ///
  /// Returns connected socket ready for data transfer
  Future<Socket> connect(
    InternetAddress targetAddress,
    int targetPort, {
    Duration? timeout,
  }) async {
    try {
      _log.fine(
          'Connecting to $targetAddress:$targetPort via SOCKS5 proxy ${config.host}:${config.port}');

      // Connect to proxy server
      final proxySocket = await Socket.connect(
        config.host,
        config.port,
        timeout: timeout ?? const Duration(seconds: 30),
      );

      try {
        // Step 1: Authentication negotiation
        await _negotiateAuth(proxySocket);

        // Step 2: Connect to target
        await _connectToTarget(proxySocket, targetAddress, targetPort);

        return proxySocket;
      } catch (e) {
        await proxySocket.close();
        rethrow;
      }
    } catch (e, stackTrace) {
      _log.warning('SOCKS5 connection failed: $targetAddress:$targetPort', e,
          stackTrace);
      rethrow;
    }
  }

  /// Negotiate authentication method (SOCKS5 handshake)
  Future<void> _negotiateAuth(Socket socket) async {
    // Build authentication request
    final authMethods = <int>[];

    if (config.requiresAuth) {
      // Username/Password authentication (method 0x02)
      authMethods.add(0x02);
    }

    // No authentication (method 0x00)
    authMethods.add(0x00);

    final request = Uint8List(2 + authMethods.length);
    request[0] = 0x05; // SOCKS version 5
    request[1] = authMethods.length; // Number of methods
    for (var i = 0; i < authMethods.length; i++) {
      request[2 + i] = authMethods[i];
    }

    // Send authentication request
    socket.add(request);
    await socket.flush();

    // Receive server response
    final response = await _readBytes(socket, 2);
    if (response[0] != 0x05) {
      throw Exception('Invalid SOCKS5 version in response: ${response[0]}');
    }

    final selectedMethod = response[1];

    // Handle authentication based on selected method
    if (selectedMethod == 0x02) {
      // Username/Password authentication
      await _authenticateUsernamePassword(socket);
    } else if (selectedMethod == 0x00) {
      // No authentication required
      _log.fine('SOCKS5: No authentication required');
    } else if (selectedMethod == 0xFF) {
      throw Exception('SOCKS5: No acceptable authentication method');
    } else {
      throw Exception('SOCKS5: Unknown authentication method: $selectedMethod');
    }
  }

  /// Authenticate using username/password
  Future<void> _authenticateUsernamePassword(Socket socket) async {
    if (!config.requiresAuth) {
      throw Exception('SOCKS5: Username/password required but not provided');
    }

    final username = utf8.encode(config.username ?? '');
    final password = utf8.encode(config.password ?? '');

    if (username.length > 255 || password.length > 255) {
      throw Exception('SOCKS5: Username or password too long');
    }

    final request = Uint8List(3 + username.length + password.length);
    request[0] = 0x01; // Username/Password version
    request[1] = username.length;
    request.setRange(2, 2 + username.length, username);
    request[2 + username.length] = password.length;
    request.setRange(
        3 + username.length, 3 + username.length + password.length, password);

    socket.add(request);
    await socket.flush();

    final response = await _readBytes(socket, 2);
    if (response[0] != 0x01) {
      throw Exception('Invalid username/password version: ${response[0]}');
    }

    if (response[1] != 0x00) {
      throw Exception('SOCKS5: Authentication failed');
    }

    _log.fine('SOCKS5: Username/password authentication successful');
  }

  /// Connect to target address through proxy
  Future<void> _connectToTarget(
    Socket socket,
    InternetAddress targetAddress,
    int targetPort,
  ) async {
    // Build CONNECT request
    Uint8List request;

    if (targetAddress.type == InternetAddressType.IPv4) {
      // IPv4 address (type 0x01)
      final addrBytes = targetAddress.rawAddress;
      request = Uint8List(4 + 2 + addrBytes.length);
      request[0] = 0x05; // SOCKS version
      request[1] = 0x01; // CONNECT command
      request[2] = 0x00; // Reserved
      request[3] = 0x01; // IPv4 address type
      request.setRange(4, 4 + addrBytes.length, addrBytes);
      final portOffset = 4 + addrBytes.length;
      request[portOffset] = (targetPort >> 8) & 0xFF;
      request[portOffset + 1] = targetPort & 0xFF;
    } else if (targetAddress.type == InternetAddressType.IPv6) {
      // IPv6 address (type 0x04)
      final addrBytes = targetAddress.rawAddress;
      request = Uint8List(4 + 2 + addrBytes.length);
      request[0] = 0x05; // SOCKS version
      request[1] = 0x01; // CONNECT command
      request[2] = 0x00; // Reserved
      request[3] = 0x04; // IPv6 address type
      request.setRange(4, 4 + addrBytes.length, addrBytes);
      final portOffset = 4 + addrBytes.length;
      request[portOffset] = (targetPort >> 8) & 0xFF;
      request[portOffset + 1] = targetPort & 0xFF;
    } else {
      throw Exception('Unsupported address type: ${targetAddress.type}');
    }

    // Send CONNECT request
    socket.add(request);
    await socket.flush();

    // Receive response
    final response = await _readBytes(socket, 4);
    if (response[0] != 0x05) {
      throw Exception('Invalid SOCKS5 version in response: ${response[0]}');
    }

    final reply = response[1];
    if (reply != 0x00) {
      final errorMsg = _getSocks5Error(reply);
      throw Exception('SOCKS5 connection failed: $errorMsg (code: $reply)');
    }

    final addressType = response[3];

    // Read bound address (we don't need it, but must read it)
    if (addressType == 0x01) {
      // IPv4
      await _readBytes(socket, 4);
    } else if (addressType == 0x03) {
      // Domain name
      final nameLen = (await _readBytes(socket, 1))[0];
      await _readBytes(socket, nameLen);
    } else if (addressType == 0x04) {
      // IPv6
      await _readBytes(socket, 16);
    }

    // Read bound port (we don't need it, but must read it)
    await _readBytes(socket, 2);

    _log.fine('SOCKS5: Connected to $targetAddress:$targetPort');
  }

  /// Read exact number of bytes from socket
  Future<Uint8List> _readBytes(Socket socket, int count) async {
    final buffer = <int>[];
    while (buffer.length < count) {
      final data = await socket.first;
      buffer.addAll(data);
      if (buffer.length >= count) break;
    }
    return Uint8List.fromList(buffer.sublist(0, count));
  }

  /// Get SOCKS5 error message
  String _getSocks5Error(int code) {
    switch (code) {
      case 0x01:
        return 'General SOCKS server failure';
      case 0x02:
        return 'Connection not allowed by ruleset';
      case 0x03:
        return 'Network unreachable';
      case 0x04:
        return 'Host unreachable';
      case 0x05:
        return 'Connection refused';
      case 0x06:
        return 'TTL expired';
      case 0x07:
        return 'Command not supported';
      case 0x08:
        return 'Address type not supported';
      default:
        return 'Unknown error (code: $code)';
    }
  }
}
