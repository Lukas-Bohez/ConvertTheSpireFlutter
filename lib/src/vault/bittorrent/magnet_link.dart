import 'dart:core';

class MagnetLink {
  final String? infoHashV1;
  final String? infoHashV2;
  final String? displayName;
  final List<String> trackers;
  final List<String> peers;

  MagnetLink({
    this.infoHashV1,
    this.infoHashV2,
    this.displayName,
    List<String>? trackers,
    List<String>? peers,
  }) : trackers = trackers ?? [],
       peers = peers ?? [];

  factory MagnetLink.parse(String uri) {
    final raw = uri.trim();
    if (!raw.toLowerCase().startsWith('magnet:')) {
      throw FormatException('Not a magnet link');
    }

    final params = <String, List<String>>{};
    final queryIndex = raw.indexOf('?');
    final query = queryIndex >= 0 ? raw.substring(queryIndex + 1) : '';
    if (query.isNotEmpty) {
      for (final pair in query.split('&')) {
        if (pair.isEmpty) continue;
        final eq = pair.indexOf('=');
        final rawKey = eq < 0 ? pair : pair.substring(0, eq);
        final rawValue = eq < 0 ? '' : pair.substring(eq + 1);
        final key = _safeDecode(rawKey).toLowerCase();
        final value = _safeDecode(rawValue);
        if (key.isEmpty) continue;
        params.putIfAbsent(key, () => <String>[]).add(value);
      }
    }

    String? infoHashV1;
    String? infoHashV2;
    String? displayName;
    final trackers = <String>[];
    final peers = <String>[];

    for (final entry in params.entries) {
      final key = entry.key;
      for (final value in entry.value) {
        if (key == 'xt') {
          final normalizedXt = value.trim().toLowerCase();
          if (normalizedXt.startsWith('urn:btih:')) {
            final token = value.substring(9).trim();
            final parsedBtih = _normalizeBtih(token);
            if (parsedBtih != null) {
              infoHashV1 = parsedBtih;
            }
          } else if (normalizedXt.startsWith('urn:btmh:')) {
            final hash = value.substring(9).trim().toLowerCase();
            final parsedBtmh = _normalizeBtmh(hash);
            if (parsedBtmh != null) {
              infoHashV2 = parsedBtmh;
            }
          }
        } else if (key == 'dn') {
          final dn = value.trim();
          if (dn.isNotEmpty) {
            displayName = _stripWrappingQuotes(dn);
          }
        } else if (key == 'tr') {
          final tracker = value.trim();
          if (tracker.isNotEmpty && !trackers.contains(tracker)) {
            trackers.add(tracker);
          }
        } else if (key == 'x.pe') {
          final peer = value.trim();
          if (peer.isNotEmpty && !peers.contains(peer)) {
            peers.add(peer);
          }
        }
      }
    }

    return MagnetLink(
      infoHashV1: infoHashV1,
      infoHashV2: infoHashV2,
      displayName: displayName,
      trackers: trackers,
      peers: peers,
    );
  }

  String toUri() {
    final params = <String>[];
    if (infoHashV1 != null) {
      params.add('xt=urn:btih:$infoHashV1');
    }
    if (infoHashV2 != null) {
      params.add('xt=urn:btmh:1220$infoHashV2');
    }
    if (displayName != null) {
      params.add('dn=${Uri.encodeComponent(displayName!)}');
    }
    for (final t in trackers) {
      params.add('tr=${Uri.encodeComponent(t)}');
    }
    for (final p in peers) {
      params.add('x.pe=${Uri.encodeComponent(p)}');
    }
    return 'magnet:?${params.join('&')}';
  }

  static String _safeDecode(String value) {
    if (value.isEmpty) return value;
    final plusFixed = value.replaceAll('+', ' ');
    try {
      return Uri.decodeComponent(plusFixed);
    } catch (_) {
      return plusFixed;
    }
  }

  static String _stripWrappingQuotes(String value) {
    if (value.length < 2) return value;
    final first = value[0];
    final last = value[value.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  static String? _normalizeBtih(String token) {
    if (RegExp(r'^[A-Fa-f0-9]{40}$').hasMatch(token)) {
      return token.toLowerCase();
    }
    if (RegExp(r'^[A-Za-z2-7]{32}$').hasMatch(token)) {
      return token.toUpperCase();
    }
    return null;
  }

  static String? _normalizeBtmh(String token) {
    final hexOnly = token.trim().toLowerCase();
    if (!RegExp(r'^[A-Fa-f0-9]+$').hasMatch(hexOnly)) return null;

    var normalized = hexOnly;
    if (normalized.startsWith('1220') && normalized.length > 62) {
      normalized = normalized.substring(4);
    }

    if (normalized.length > 64) {
      normalized = normalized.substring(normalized.length - 64);
    }

    if (RegExp(r'^[A-Fa-f0-9]{62}$').hasMatch(normalized) ||
        RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(normalized)) {
      return normalized;
    }
    return null;
  }
}
