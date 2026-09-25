import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'ip_filter.dart';

var _log = Logger('PeerGuardianParser');

/// Parser for PeerGuardian IP filter format
///
/// PeerGuardian format is a text-based format with the following structure:
/// - Lines starting with '#' are comments
/// - Empty lines are ignored
/// - Each rule line contains: IP range or CIDR notation
/// - Format examples:
///   - Single IP: "192.168.1.1"
///   - IP range: "192.168.1.0-192.168.1.255"
///   - CIDR: "192.168.1.0/24"
///   - With description: "192.168.1.0/24 : Some description"
class PeerGuardianParser {
  /// Parse PeerGuardian format file and add rules to IP filter
  ///
  /// [file] - Path to the file
  /// [filter] - IP filter to populate
  /// Returns number of rules added
  static Future<int> parseFile(String file, IPFilter filter) async {
    try {
      final lines = await File(file).readAsLines();
      return parseLines(lines, filter);
    } catch (e, stackTrace) {
      _log.warning('Failed to parse PeerGuardian file: $file', e, stackTrace);
      return 0;
    }
  }

  /// Parse PeerGuardian format from string
  static int parseString(String content, IPFilter filter) {
    final lines = content.split('\n');
    return parseLines(lines, filter);
  }

  /// Parse PeerGuardian format from lines
  static int parseLines(List<String> lines, IPFilter filter) {
    int rulesAdded = 0;

    for (var line in lines) {
      // Trim whitespace
      line = line.trim();

      // Skip empty lines and comments
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      // Remove description if present (everything after ':')
      final rulePart = line.split(':').first.trim();

      try {
        // Try to parse as CIDR
        if (rulePart.contains('/')) {
          filter.addCIDRFromString(rulePart);
          rulesAdded++;
        }
        // Try to parse as IP range
        else if (rulePart.contains('-')) {
          final rangeRules = _parseIPRange(rulePart);
          for (final rule in rangeRules) {
            if (rule.contains('/')) {
              filter.addCIDRFromString(rule);
            } else {
              filter.addIPFromString(rule);
            }
            rulesAdded++;
          }
        }
        // Try to parse as single IP
        else {
          filter.addIPFromString(rulePart);
          rulesAdded++;
        }
      } catch (e) {
        _log.fine('Failed to parse line: $line, error: $e');
        // Continue parsing other lines
      }
    }

    _log.info('Parsed PeerGuardian format: added $rulesAdded rules');
    return rulesAdded;
  }

  /// Parse IP range (e.g., "192.168.1.0-192.168.1.255")
  static List<String> _parseIPRange(String range) {
    final parts = range.split('-');
    if (parts.length != 2) {
      throw FormatException('Invalid IP range format: $range');
    }

    final startIP = InternetAddress.tryParse(parts[0].trim());
    final endIP = InternetAddress.tryParse(parts[1].trim());

    if (startIP == null || endIP == null) {
      throw FormatException('Invalid IP addresses in range: $range');
    }

    if (startIP.type != InternetAddressType.IPv4 ||
        endIP.type != InternetAddressType.IPv4) {
      throw FormatException('Only IPv4 addresses are supported');
    }

    // Convert to CIDR blocks
    final start = _ipToInt(startIP);
    final end = _ipToInt(endIP);

    if (start > end) {
      throw FormatException('Start IP must be <= end IP: $range');
    }

    final blocks = _ipRangeToCIDR(start, end);
    return blocks.map((b) => b.toString()).toList();
  }

  /// Convert IP address to 32-bit integer
  static int _ipToInt(InternetAddress address) {
    final bytes = address.rawAddress;
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }

  /// Convert 32-bit integer to IP address
  static InternetAddress _intToIP(int value) {
    final bytes = Uint8List.fromList([
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
    return InternetAddress.fromRawAddress(bytes);
  }

  /// Convert IP range to CIDR blocks
  static List<CIDRBlock> _ipRangeToCIDR(int startIP, int endIP) {
    final blocks = <CIDRBlock>[];

    int current = startIP;
    while (current <= endIP) {
      // Find the largest CIDR block that starts at current IP
      int prefixLength = 32;
      int blockSize = 1;

      while (prefixLength > 0) {
        final nextBlockSize = blockSize * 2;
        final nextBlockEnd = current + nextBlockSize - 1;

        // Check if this block fits within the range
        if (nextBlockEnd <= endIP && (current & (nextBlockSize - 1)) == 0) {
          blockSize = nextBlockSize;
          prefixLength--;
        } else {
          break;
        }
      }

      // Create CIDR block
      final network = _intToIP(current);
      blocks.add(CIDRBlock(network, prefixLength));

      current += blockSize;
    }

    return blocks;
  }
}
