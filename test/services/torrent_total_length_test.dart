import 'dart:typed_data';

import 'package:convert_the_spire_reborn/src/vault/bittorrent/bencode.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_engine_service.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart' as dt;
import 'package:flutter_test/flutter_test.dart';

/// A .torrent with the given files, 16 KiB pieces and dummy piece hashes.
Uint8List _torrent(Map<String, int> files) {
  final total = files.values.fold<int>(0, (a, b) => a + b);
  final pieces = (total + 16383) ~/ 16384;
  final info = <String, dynamic>{
    'name': 'Season 1',
    'piece length': 16384,
    'pieces': Uint8List(20 * pieces),
  };
  if (files.length == 1) {
    info['length'] = files.values.single;
  } else {
    info['files'] = [
      for (final e in files.entries)
        {
          'length': e.value,
          'path': [e.key],
        },
    ];
  }
  return bencode({'announce': 'udp://tracker.example:1337', 'info': info});
}

void main() {
  test('a multi-file torrent gets its total size as length', () {
    final parsed = dt.TorrentParser.parseBytes(
        _torrent({'e01.mkv': 50000, 'e02.mkv': 70000, 'subs.srt': 1234}));
    // dtorrent_task_v2 leaves length unset for multi-file torrents, and the
    // task then reports progress 0 and "0 bytes left" to trackers.
    expect(parsed.length, isNull);

    final model = TorrentEngineService.withTotalLength(parsed);
    expect(model.length, 121234);
    expect(model.infoHashBuffer, parsed.infoHashBuffer);
    expect(model.files.map((f) => f.path), parsed.files.map((f) => f.path));
    expect(model.pieces!.length, parsed.pieces!.length);
    expect(model.announces, parsed.announces);
  });

  test('a single-file torrent is left as it is', () {
    final parsed = dt.TorrentParser.parseBytes(_torrent({'movie.mkv': 99999}));
    expect(parsed.length, 99999);
    expect(identical(TorrentEngineService.withTotalLength(parsed), parsed),
        isTrue);
  });
}
