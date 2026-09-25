import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'upnp_client.dart';
import 'natpmp_client.dart';

/// Logger instance for PortForwardingManager
final _log = Logger('PortForwardingManager');

/// Port forwarding method
enum PortForwardingMethod {
  /// UPnP IGD protocol
  upnp,

  /// NAT-PMP protocol
  natpmp,

  /// Automatic (try UPnP first, then NAT-PMP)
  auto,
}

/// Port forwarding result
class PortForwardingResult {
  /// Whether port forwarding was successful
  final bool success;

  /// Method used (if successful)
  final PortForwardingMethod? method;

  /// Error message (if failed)
  final String? error;

  /// External IP address (if available)
  final InternetAddress? externalIP;

  PortForwardingResult({
    required this.success,
    this.method,
    this.error,
    this.externalIP,
  });

  @override
  String toString() {
    if (success) {
      return 'PortForwardingResult(success: true, method: $method, externalIP: $externalIP)';
    }
    return 'PortForwardingResult(success: false, error: $error)';
  }
}

/// Manager for automatic port forwarding using UPnP and NAT-PMP
///
/// Automatically discovers and uses available port forwarding method
/// to forward ports for BitTorrent connections.
class PortForwardingManager {
  UPnPClient? _upnpClient;
  NATPMPClient? _natpmpClient;

  /// Preferred method (auto by default)
  final PortForwardingMethod preferredMethod;

  /// Discovered method (set after successful discovery)
  PortForwardingMethod? _discoveredMethod;

  /// Active port mappings (port -> method)
  final Map<int, PortForwardingMethod> _activeMappings = {};

  /// Lease renewal timers (port -> timer)
  final Map<int, Timer> _leaseRenewalTimers = {};

  /// Timeout for operations
  final Duration timeout;

  PortForwardingManager({
    this.preferredMethod = PortForwardingMethod.auto,
    this.timeout = const Duration(seconds: 10),
  });

  /// Discover available port forwarding method
  ///
  /// Returns the method that works, or null if none available
  Future<PortForwardingMethod?> discover() async {
    if (_discoveredMethod != null) {
      return _discoveredMethod;
    }

    _log.info('Discovering port forwarding method...');

    // Try preferred method first
    if (preferredMethod == PortForwardingMethod.upnp ||
        preferredMethod == PortForwardingMethod.auto) {
      _upnpClient ??= UPnPClient(timeout: timeout);
      final gateway = await _upnpClient!.discoverGateway();
      if (gateway != null) {
        _discoveredMethod = PortForwardingMethod.upnp;
        _log.info('UPnP port forwarding available');
        return _discoveredMethod;
      }
    }

    if (preferredMethod == PortForwardingMethod.natpmp ||
        preferredMethod == PortForwardingMethod.auto) {
      _natpmpClient ??= NATPMPClient(timeout: timeout);
      final gateway = await _natpmpClient!.discoverGateway();
      if (gateway != null) {
        _discoveredMethod = PortForwardingMethod.natpmp;
        _log.info('NAT-PMP port forwarding available');
        return _discoveredMethod;
      }
    }

    _log.warning('No port forwarding method available');
    return null;
  }

  /// Forward a port
  ///
  /// [port] - Port to forward (both external and internal)
  /// [protocol] - 'TCP' or 'UDP' (for UPnP) or 1/2 (for NAT-PMP)
  /// [description] - Description for the port mapping
  /// [leaseDuration] - Lease duration in seconds (0 = permanent)
  Future<PortForwardingResult> forwardPort({
    required int port,
    String protocol = 'TCP',
    String description = 'dtorrent_task_v2',
    int leaseDuration = 0,
  }) async {
    try {
      // Discover method if not already discovered
      final method = await discover();
      if (method == null) {
        return PortForwardingResult(
          success: false,
          error: 'No port forwarding method available',
        );
      }

      // Get local IP address
      final localIP = await _getLocalIP();
      if (localIP == null) {
        return PortForwardingResult(
          success: false,
          error: 'Failed to determine local IP address',
        );
      }

      bool success = false;
      InternetAddress? externalIP;

      if (method == PortForwardingMethod.upnp) {
        _upnpClient ??= UPnPClient(timeout: timeout);
        success = await _upnpClient!.addPortMapping(
          externalPort: port,
          internalPort: port,
          internalClient: localIP,
          protocol: protocol,
          description: description,
          leaseDuration: leaseDuration,
        );
        if (success) {
          externalIP = await _upnpClient!.getExternalIP().then(
                (ip) => ip != null ? InternetAddress(ip) : null,
              );
        }
      } else if (method == PortForwardingMethod.natpmp) {
        _natpmpClient ??= NATPMPClient(timeout: timeout);
        final protocolCode = protocol.toUpperCase() == 'UDP' ? 2 : 1;
        success = await _natpmpClient!.addPortMapping(
          externalPort: port,
          internalPort: port,
          protocol: protocolCode,
          leaseDuration: leaseDuration > 0 ? leaseDuration : 3600,
        );
        if (success) {
          externalIP = await _natpmpClient!.getExternalIP();
        }
      }

      if (success) {
        _activeMappings[port] = method;
        _log.info('Port $port forwarded successfully using $method');

        // Schedule lease renewal for NAT-PMP (if lease duration > 0)
        if (method == PortForwardingMethod.natpmp && leaseDuration > 0) {
          _scheduleLeaseRenewal(port, leaseDuration, protocol);
        }

        return PortForwardingResult(
          success: true,
          method: method,
          externalIP: externalIP,
        );
      } else {
        return PortForwardingResult(
          success: false,
          error: 'Failed to forward port using $method',
        );
      }
    } catch (e, stackTrace) {
      _log.warning('Error forwarding port $port', e, stackTrace);
      return PortForwardingResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Remove port forwarding
  ///
  /// [port] - Port to remove
  /// [protocol] - 'TCP' or 'UDP'
  Future<bool> removePortForwarding({
    required int port,
    String protocol = 'TCP',
  }) async {
    try {
      final method = _activeMappings[port];
      if (method == null) {
        _log.warning('Port $port is not in active mappings');
        return false;
      }

      bool success = false;

      if (method == PortForwardingMethod.upnp) {
        _upnpClient ??= UPnPClient(timeout: timeout);
        success = await _upnpClient!.deletePortMapping(
          externalPort: port,
          protocol: protocol,
        );
      } else if (method == PortForwardingMethod.natpmp) {
        _natpmpClient ??= NATPMPClient(timeout: timeout);
        final protocolCode = protocol.toUpperCase() == 'UDP' ? 2 : 1;
        success = await _natpmpClient!.deletePortMapping(
          externalPort: port,
          protocol: protocolCode,
        );
      }

      if (success) {
        _activeMappings.remove(port);
        _leaseRenewalTimers[port]?.cancel();
        _leaseRenewalTimers.remove(port);
        _log.info('Port $port forwarding removed');
      }

      return success;
    } catch (e, stackTrace) {
      _log.warning('Error removing port forwarding for $port', e, stackTrace);
      return false;
    }
  }

  /// Remove all active port forwardings
  Future<void> removeAllPortForwardings() async {
    final ports = List<int>.from(_activeMappings.keys);
    for (var port in ports) {
      await removePortForwarding(port: port);
    }
    // Cancel all renewal timers
    for (var timer in _leaseRenewalTimers.values) {
      timer.cancel();
    }
    _leaseRenewalTimers.clear();
  }

  /// Schedule lease renewal for NAT-PMP port mapping
  ///
  /// Renews the lease at 50% of the lease duration to ensure continuity
  void _scheduleLeaseRenewal(int port, int leaseDuration, String protocol) {
    // Cancel existing timer if any
    _leaseRenewalTimers[port]?.cancel();

    // Renew at 50% of lease duration (best practice for NAT-PMP)
    final renewalDelay = Duration(seconds: leaseDuration ~/ 2);
    if (renewalDelay.inSeconds < 1) return; // Skip if too short

    _leaseRenewalTimers[port] = Timer(renewalDelay, () async {
      _log.info('Renewing NAT-PMP lease for port $port');
      final method = _activeMappings[port];
      if (method == PortForwardingMethod.natpmp) {
        final protocolCode = protocol.toUpperCase() == 'UDP' ? 2 : 1;
        final success = await _natpmpClient?.addPortMapping(
          externalPort: port,
          internalPort: port,
          protocol: protocolCode,
          leaseDuration: leaseDuration,
        );
        if (success == true) {
          // Schedule next renewal
          _scheduleLeaseRenewal(port, leaseDuration, protocol);
        } else {
          _log.warning('Failed to renew NAT-PMP lease for port $port');
        }
      }
    });
  }

  /// Get local IP address
  Future<String?> _getLocalIP() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          // Skip loopback
          if (addr.isLoopback) continue;
          // Prefer non-link-local addresses
          if (!addr.isLinkLocal) {
            return addr.address;
          }
        }
      }

      // Fallback: use first non-loopback address
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }

      return null;
    } catch (e) {
      _log.warning('Failed to get local IP address', e);
      return null;
    }
  }

  /// Get external IP address
  Future<InternetAddress?> getExternalIP() async {
    final method = await discover();
    if (method == null) {
      return null;
    }

    try {
      if (method == PortForwardingMethod.upnp) {
        _upnpClient ??= UPnPClient(timeout: timeout);
        final ipStr = await _upnpClient!.getExternalIP();
        return ipStr != null ? InternetAddress(ipStr) : null;
      } else if (method == PortForwardingMethod.natpmp) {
        _natpmpClient ??= NATPMPClient(timeout: timeout);
        return await _natpmpClient!.getExternalIP();
      }
    } catch (e) {
      _log.warning('Failed to get external IP', e);
    }

    return null;
  }

  /// Get active port mappings
  Map<int, PortForwardingMethod> get activeMappings =>
      Map.unmodifiable(_activeMappings);

  /// Check if port forwarding is available
  Future<bool> isAvailable() async {
    final method = await discover();
    return method != null;
  }
}
