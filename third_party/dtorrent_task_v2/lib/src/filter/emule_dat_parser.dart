import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'ip_filter.dart';

var _log = Logger('EmuleDatParser');

/// Parser for eMule IP filter dat format
///
/// eMule dat format structure:
/// - Binary format
/// - Header: 4 bytes (version/format identifier)
/// - Records: Each record contains:
///   - IP range start (4 bytes, big-endian)
///   - IP range end (4 bytes, big-endian)
///   - Access level (1 byte, 0-255)
///   - Description length (1 byte)
///   - Description (UTF-8 string)
class EmuleDatParser {
  /// Parse eMule dat file and add rules to IP filter
  ///
  /// [file] - Path to the dat file
  /// [filter] - IP filter to populate
  /// [minAccessLevel] - Minimum access level to block (default: 1, blocks all)
  /// Returns number of rules added
  static Future<int> parseFile(
    String file,
    IPFilter filter, {
    int minAccessLevel = 1,
  }) async {
    try {
      final fileData = await File(file).readAsBytes();
      return parseBytes(fileData, filter, minAccessLevel: minAccessLevel);
    } catch (e, stackTrace) {
      _log.warning('Failed to parse eMule dat file: $file', e, stackTrace);
      return 0;
    }
  }

  /// Parse eMule dat from bytes
  static int parseBytes(
    List<int> data,
    IPFilter filter, {
    int minAccessLevel = 1,
  }) {
    if (data.length < 4) {
      _log.warning('eMule dat file too short');
      return 0;
    }

    int rulesAdded = 0;
    int offset = 0;

    // Read header (4 bytes)
    // Version 1: 0x00000001
    // Version 2: 0x00000002
    final header = _readUint32(data, offset);
    offset += 4;

    _log.fine('eMule dat header: 0x${header.toRadixString(16)}');

    // Parse records
    while (offset + 10 <= data.length) {
      // Read IP range start (4 bytes, big-endian)
      final startIP = _readUint32(data, offset);
      offset += 4;

      // Read IP range end (4 bytes, big-endian)
      final endIP = _readUint32(data, offset);
      offset += 4;

      // Read access level (1 byte)
      final accessLevel = data[offset];
      offset += 1;

      // Read description length (1 byte)
      final descLength = data[offset];
      offset += 1;

      // Skip description if present
      if (descLength > 0 && offset + descLength <= data.length) {
        // Description is UTF-8 encoded
        offset += descLength;
      }

      // Add to filter if access level meets threshold
      if (accessLevel >= minAccessLevel) {
        // Convert IP range to CIDR blocks
        final blocks = _ipRangeToCIDR(startIP, endIP);
        for (final block in blocks) {
          filter.addCIDR(block);
          rulesAdded++;
        }
      }
    }

    _log.info('Parsed eMule dat: added $rulesAdded rules');
    return rulesAdded;
  }

  /// Convert IP range to CIDR blocks
  static List<CIDRBlock> _ipRangeToCIDR(int startIP, int endIP) {
    final blocks = <CIDRBlock>[];

    if (startIP > endIP) {
      _log.warning('Invalid IP range: start > end');
      return blocks;
    }

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
      final network = InternetAddress.fromRawAddress(
          Uint8List.fromList(_uint32ToBytes(current)));
      blocks.add(CIDRBlock(network, prefixLength));

      current += blockSize;
    }

    return blocks;
  }

  /// Read 32-bit unsigned integer (big-endian)
  static int _readUint32(List<int> data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  /// Convert 32-bit integer to 4-byte list (big-endian)
  static List<int> _uint32ToBytes(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }
}
