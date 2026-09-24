import 'dart:typed_data';

/// Info-hash and magnet helpers shared by the magnet parser, the torrent
/// service and the engine.
///
/// A BitTorrent v1 info-hash is 20 bytes. Magnet links write it either as 40
/// hex digits or as 32 base32 characters (nyaa and many anime trackers use
/// base32). Everything inside the app works with the lowercase hex form, so a
/// torrent added from either spelling gets the same id, the same cache file
/// and the same bytes on the wire.
class InfoHash {
  InfoHash._();

  static final RegExp _hex40 = RegExp(r'^[A-Fa-f0-9]{40}$');
  static final RegExp _base32 = RegExp(r'^[A-Za-z2-7]{32}$');
  static const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// The lowercase 40-hex form of a v1 info-hash written as hex or base32,
  /// or null when [token] is neither.
  static String? normalizeBtih(String token) {
    final value = token.trim();
    if (_hex40.hasMatch(value)) return value.toLowerCase();
    if (_base32.hasMatch(value)) {
      final bytes = _base32Decode(value.toUpperCase());
      if (bytes != null && bytes.length == 20) return toHex(bytes);
    }
    return null;
  }

  /// The 20 raw bytes of a v1 info-hash written as hex or base32 - including
  /// torrent ids saved by older versions, which kept the base32 spelling.
  static Uint8List? bytesOf(String? id) {
    if (id == null) return null;
    final hex = normalizeBtih(id);
    if (hex == null) return null;
    final out = Uint8List(20);
    for (var i = 0; i < 20; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String toHex(List<int> bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  static Uint8List? _base32Decode(String input) {
    var buffer = 0;
    var bits = 0;
    final out = <int>[];
    for (final char in input.split('')) {
      final value = _base32Alphabet.indexOf(char);
      if (value < 0) return null;
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
    }
    return Uint8List.fromList(out);
  }

  /// The tracker URLs in a magnet link (`tr=` and the tiered `tr.1=` form),
  /// decoded, de-duplicated and in the order the link lists them.
  ///
  /// Only trackers the engine can talk to are kept: http, https and udp.
  /// WebTorrent `wss://` trackers only serve browser peers.
  static List<String> magnetTrackers(String magnet) {
    final query = _queryOf(magnet);
    if (query.isEmpty) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final pair in query.split('&')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = pair.substring(0, eq).toLowerCase();
      if (key != 'tr' && !RegExp(r'^tr\.\d+$').hasMatch(key)) continue;
      final url = _decode(pair.substring(eq + 1)).trim();
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty) continue;
      if (!const {'http', 'https', 'udp'}.contains(uri.scheme.toLowerCase())) {
        continue;
      }
      if (seen.add(url)) out.add(url);
    }
    return out;
  }

  /// The web seeds (`ws=`) in a magnet link, decoded.
  static List<String> magnetWebSeeds(String magnet) {
    final query = _queryOf(magnet);
    final out = <String>[];
    for (final pair in query.split('&')) {
      final eq = pair.indexOf('=');
      if (eq <= 0 || pair.substring(0, eq).toLowerCase() != 'ws') continue;
      final url = _decode(pair.substring(eq + 1)).trim();
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
        continue;
      }
      if (!out.contains(url)) out.add(url);
    }
    return out;
  }

  /// A clean magnet link for the BitTorrent engine: the hex info-hash plus the
  /// link's own trackers and web seeds, re-encoded so a display name with a
  /// stray `%` or `&` in it cannot make the engine reject the link.
  static String engineMagnet(String btihHex, {String sourceMagnet = ''}) {
    final parts = <String>['xt=urn:btih:${btihHex.toLowerCase()}'];
    for (final tracker in magnetTrackers(sourceMagnet)) {
      parts.add('tr=${Uri.encodeComponent(tracker)}');
    }
    for (final seed in magnetWebSeeds(sourceMagnet)) {
      parts.add('ws=${Uri.encodeComponent(seed)}');
    }
    return 'magnet:?${parts.join('&')}';
  }

  static String _queryOf(String magnet) {
    final index = magnet.indexOf('?');
    return index < 0 ? '' : magnet.substring(index + 1);
  }

  static String _decode(String value) {
    try {
      return Uri.decodeComponent(value.replaceAll('+', ' '));
    } catch (_) {
      return value;
    }
  }
}
