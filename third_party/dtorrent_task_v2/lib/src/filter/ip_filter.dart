import 'dart:io';
import 'package:logging/logging.dart';

var _log = Logger('IPFilter');

/// IP filtering mode
enum IPFilterMode {
  /// Blacklist mode: block IPs in the filter
  blacklist,

  /// Whitelist mode: allow only IPs in the filter
  whitelist,
}

/// Represents a CIDR block (IP address range)
class CIDRBlock {
  final InternetAddress network;
  final int prefixLength;

  CIDRBlock(this.network, this.prefixLength) {
    if (prefixLength < 0 || prefixLength > 32) {
      throw ArgumentError('Prefix length must be between 0 and 32');
    }
  }

  /// Parse CIDR notation (e.g., "192.168.1.0/24")
  factory CIDRBlock.parse(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) {
      throw FormatException('Invalid CIDR format: $cidr');
    }

    final address = InternetAddress.tryParse(parts[0]);
    if (address == null) {
      throw FormatException('Invalid IP address: ${parts[0]}');
    }

    if (address.type != InternetAddressType.IPv4) {
      throw FormatException('Only IPv4 addresses are supported');
    }

    final prefixLength = int.tryParse(parts[1]);
    if (prefixLength == null || prefixLength < 0 || prefixLength > 32) {
      throw FormatException('Invalid prefix length: ${parts[1]}');
    }

    return CIDRBlock(address, prefixLength);
  }

  /// Check if an IP address is within this CIDR block
  bool contains(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) {
      return false;
    }

    final ipBytes = address.rawAddress;
    final networkBytes = network.rawAddress;

    // Calculate number of bytes to check
    final fullBytes = prefixLength ~/ 8;
    final remainingBits = prefixLength % 8;

    // Check full bytes
    for (int i = 0; i < fullBytes; i++) {
      if (ipBytes[i] != networkBytes[i]) {
        return false;
      }
    }

    // Check remaining bits
    if (remainingBits > 0 && fullBytes < 4) {
      final mask = (0xFF << (8 - remainingBits)) & 0xFF;
      if ((ipBytes[fullBytes] & mask) != (networkBytes[fullBytes] & mask)) {
        return false;
      }
    }

    return true;
  }

  @override
  String toString() => '${network.address}/$prefixLength';

  @override
  bool operator ==(Object other) =>
      other is CIDRBlock &&
      network.address == other.network.address &&
      prefixLength == other.prefixLength;

  @override
  int get hashCode => Object.hash(network.address, prefixLength);
}

/// IP filter for blocking/allowing IP addresses and CIDR blocks
class IPFilter {
  IPFilterMode _mode = IPFilterMode.blacklist;
  final Set<InternetAddress> _ipAddresses = {};
  final Set<CIDRBlock> _cidrBlocks = {};

  /// Current filtering mode
  IPFilterMode get mode => _mode;

  /// Number of IP addresses in the filter
  int get ipCount => _ipAddresses.length;

  /// Number of CIDR blocks in the filter
  int get cidrCount => _cidrBlocks.length;

  /// Total number of rules
  int get totalRules => ipCount + cidrCount;

  /// Set filtering mode
  void setMode(IPFilterMode mode) {
    _mode = mode;
    _log.info('IP filter mode set to: $mode');
  }

  /// Add a single IP address to the filter
  void addIP(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) {
      _log.warning('Only IPv4 addresses are supported, ignoring: $address');
      return;
    }
    _ipAddresses.add(address);
    _log.fine('Added IP to filter: $address');
  }

  /// Add an IP address from string
  void addIPFromString(String ip) {
    final address = InternetAddress.tryParse(ip);
    if (address == null) {
      _log.warning('Invalid IP address: $ip');
      return;
    }
    addIP(address);
  }

  /// Add a CIDR block to the filter
  void addCIDR(CIDRBlock block) {
    _cidrBlocks.add(block);
    _log.fine('Added CIDR block to filter: $block');
  }

  /// Add a CIDR block from string (e.g., "192.168.1.0/24")
  void addCIDRFromString(String cidr) {
    try {
      final block = CIDRBlock.parse(cidr);
      addCIDR(block);
    } catch (e) {
      _log.warning('Failed to parse CIDR: $cidr, error: $e');
    }
  }

  /// Remove an IP address from the filter
  bool removeIP(InternetAddress address) {
    final removed = _ipAddresses.remove(address);
    if (removed) {
      _log.fine('Removed IP from filter: $address');
    }
    return removed;
  }

  /// Remove an IP address from string
  bool removeIPFromString(String ip) {
    final address = InternetAddress.tryParse(ip);
    if (address == null) {
      return false;
    }
    return removeIP(address);
  }

  /// Remove a CIDR block from the filter
  bool removeCIDR(CIDRBlock block) {
    final removed = _cidrBlocks.remove(block);
    if (removed) {
      _log.fine('Removed CIDR block from filter: $block');
    }
    return removed;
  }

  /// Remove a CIDR block from string
  bool removeCIDRFromString(String cidr) {
    try {
      final block = CIDRBlock.parse(cidr);
      return removeCIDR(block);
    } catch (e) {
      _log.warning('Failed to parse CIDR for removal: $cidr, error: $e');
      return false;
    }
  }

  /// Clear all IP addresses and CIDR blocks
  void clear() {
    _ipAddresses.clear();
    _cidrBlocks.clear();
    _log.info('IP filter cleared');
  }

  /// Check if an IP address is allowed
  ///
  /// Returns:
  /// - `true` if the IP is allowed
  /// - `false` if the IP is blocked
  bool isAllowed(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) {
      // For now, only IPv4 is supported
      return true;
    }

    // Check if IP is in the filter
    bool inFilter = false;

    // Check exact IP match
    if (_ipAddresses.contains(address)) {
      inFilter = true;
    } else {
      // Check CIDR blocks
      for (final block in _cidrBlocks) {
        if (block.contains(address)) {
          inFilter = true;
          break;
        }
      }
    }

    // Apply mode logic
    if (_mode == IPFilterMode.blacklist) {
      // Blacklist: block if in filter
      return !inFilter;
    } else {
      // Whitelist: allow only if in filter
      return inFilter;
    }
  }

  /// Check if an IP address is blocked
  ///
  /// Returns:
  /// - `true` if the IP is blocked
  /// - `false` if the IP is allowed
  bool isBlocked(InternetAddress address) {
    return !isAllowed(address);
  }

  /// Get all IP addresses in the filter
  Set<InternetAddress> get ipAddresses => Set.unmodifiable(_ipAddresses);

  /// Get all CIDR blocks in the filter
  Set<CIDRBlock> get cidrBlocks => Set.unmodifiable(_cidrBlocks);

  /// Export filter rules as list of strings
  List<String> exportRules() {
    final rules = <String>[];
    for (final ip in _ipAddresses) {
      rules.add(ip.address);
    }
    for (final block in _cidrBlocks) {
      rules.add(block.toString());
    }
    return rules;
  }
}
