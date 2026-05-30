import 'dart:convert';
import 'dart:typed_data';

Uint8List bencode(dynamic value) {
  if (value is int) {
    return Uint8List.fromList(utf8.encode('i${value}e'));
  }
  if (value is String) {
    final bytes = utf8.encode(value);
    final prefix = utf8.encode('${bytes.length}:');
    return Uint8List.fromList([...prefix, ...bytes]);
  }
  if (value is Uint8List) {
    final prefix = utf8.encode('${value.length}:');
    return Uint8List.fromList([...prefix, ...value]);
  }
  if (value is List) {
    final parts = <int>[];
    parts.add(0x6c); // 'l'
    for (final element in value) {
      parts.addAll(bencode(element));
    }
    parts.add(0x65); // 'e'
    return Uint8List.fromList(parts);
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) {
        final ak = _toUint8ListKey(a.key);
        final bk = _toUint8ListKey(b.key);
        return _compareBytes(ak, bk);
      });
    final parts = <int>[];
    parts.add(0x64); // 'd'
    for (final entry in entries) {
      final keyBytes = _toUint8ListKey(entry.key);
      parts.addAll(bencode(keyBytes));
      parts.addAll(bencode(entry.value));
    }
    parts.add(0x65); // 'e'
    return Uint8List.fromList(parts);
  }
  throw ArgumentError.value(value, 'value', 'Unsupported bencode type');
}

dynamic bdecode(Uint8List data) {
  int index = 0;

  dynamic decodeNext() {
    if (index >= data.length) throw const FormatException('Unexpected end of data');
    final byte = data[index];

    if (byte == 0x69) {
      // 'i'
      index++;
      final end = data.indexOf(0x65, index);
      if (end == -1) throw const FormatException('Invalid integer encoding');
      final number = int.parse(utf8.decode(data.sublist(index, end)));
      index = end + 1;
      return number;
    }

    if (byte == 0x6c) {
      // 'l'
      index++;
      final list = <dynamic>[];
      while (true) {
        if (index >= data.length) {
          throw const FormatException('Unterminated list');
        }
        if (data[index] == 0x65) {
          index++;
          return list;
        }
        list.add(decodeNext());
      }
    }

    if (byte == 0x64) {
      // 'd'
      index++;
      final map = <String, dynamic>{};
      while (true) {
        if (index >= data.length) {
          throw const FormatException('Unterminated dictionary');
        }
        if (data[index] == 0x65) {
          index++;
          return map;
        }

        final keyBytes = decodeNext();
        if (keyBytes is! Uint8List) {
          throw const FormatException('Map key must be bytes');
        }
        final key = utf8.decode(keyBytes, allowMalformed: true);
        final value = decodeNext();
        map[key] = value;
      }
    }

    if (byte >= 0x30 && byte <= 0x39) {
      final colon = data.indexOf(0x3a, index);
      if (colon == -1) throw const FormatException('Invalid string length encoding');
      final len = int.parse(utf8.decode(data.sublist(index, colon)));
      index = colon + 1;
      if (index + len > data.length) {
        throw const FormatException('String extends past end of input');
      }
      final result = data.sublist(index, index + len);
      index += len;
      return result;
    }

    throw FormatException(
      'Invalid bencode prefix: ${String.fromCharCode(byte)}',
    );
  }

  final result = decodeNext();
  if (index != data.length) {
    throw const FormatException('Extra bytes after valid bencode');
  }
  return result;
}

// Helper to look up a key by string name in a bdecoded dict
dynamic getKey(Map map, String keyName) {
  for (final entry in map.entries) {
    if (keyStr(entry.key) == keyName) return entry.value;
  }
  return null;
}

Uint8List _toUint8ListKey(dynamic key) {
  if (key is String) return Uint8List.fromList(utf8.encode(key));
  if (key is Uint8List) return key;
  throw ArgumentError.value(key, 'key', 'Unsupported map key type');
}

// Helper to compare dict keys (for UI/debug)
String keyStr(dynamic k) =>
    k is Uint8List ? utf8.decode(k, allowMalformed: true) : k.toString();

int _compareBytes(Uint8List a, Uint8List b) {
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    final diff = a[i] - b[i];
    if (diff != 0) return diff;
  }
  return a.length - b.length;
}
