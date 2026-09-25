import 'dart:convert';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_file_export.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // An info dictionary as a peer or a .torrent would have it. Its keys are
  // deliberately not in sorted order: re-encoding it would sort them and
  // change the info-hash, so the export must copy the bytes untouched.
  final info = Uint8List.fromList([
    ...ascii.encode('d4:name8:song.mp36:lengthi1234e12:piece lengthi16384e'
        '6:pieces20:'),
    ...List.generate(20, (i) => 200 + i % 50),
    ...ascii.encode('e'),
  ]);
  final infoHash = sha1.convert(info).toString();

  test('keeps the info dictionary byte for byte', () {
    final file = TorrentFileExport.build(info, trackers: [
      'udp://tracker.example:6969/announce',
      'https://tracker.example/announce',
    ]);

    final inside = TorrentFileExport.infoOf(file)!;
    expect(inside, info);
    expect(TorrentFileExport.matches(inside, infoHash), isTrue);
  });

  test('is a valid .torrent with the trackers', () {
    final file = TorrentFileExport.build(info, trackers: [
      'udp://a.example:1/announce',
      'udp://b.example:2/announce',
      'udp://a.example:1/announce',
      ' ',
    ]);

    final decoded = decode(file) as Map;
    expect(utf8.decode(decoded['announce'] as List<int>),
        'udp://a.example:1/announce');
    final tiers = (decoded['announce-list'] as List)
        .map((t) => utf8.decode((t as List).single as List<int>))
        .toList();
    expect(tiers, ['udp://a.example:1/announce', 'udp://b.example:2/announce']);
    expect(decoded.containsKey('info'), isTrue);
  });

  test('works without trackers', () {
    final file = TorrentFileExport.build(info);

    expect(TorrentFileExport.infoOf(file), info);
    expect((decode(file) as Map).containsKey('announce'), isFalse);
  });

  test('finds the info dictionary in a .torrent from elsewhere', () {
    final file = Uint8List.fromList([
      ...ascii.encode('d8:announce19:udp://t.example:1/x'
          '7:comment11:hello wor e'
          '13:creation datei1700000000e4:info'),
      ...info,
      ...ascii.encode('e'),
    ]);

    expect(TorrentFileExport.infoOf(file), info);
  });

  test('rejects what is not a torrent', () {
    expect(TorrentFileExport.infoOf(Uint8List(0)), isNull);
    expect(TorrentFileExport.infoOf(ascii.encode('not bencode')), isNull);
    expect(TorrentFileExport.infoOf(ascii.encode('d3:fooi1')), isNull);
    expect(TorrentFileExport.infoOf(ascii.encode('d3:foo3:bare')), isNull);
    expect(TorrentFileExport.matches(info, '0' * 40), isFalse);
  });

  test('reads the trackers of a magnet link', () {
    expect(
      TorrentFileExport.trackersOf(
        'magnet:?xt=urn:btih:$infoHash&dn=song'
        '&tr=udp%3A%2F%2Fa.example%3A1%2Fannounce&tr=https%3A%2F%2Fb.example',
      ),
      ['udp://a.example:1/announce', 'https://b.example'],
    );
    expect(TorrentFileExport.trackersOf(null), isEmpty);
    expect(TorrentFileExport.trackersOf('magnet:?xt=urn:btih:$infoHash'),
        isEmpty);
  });
}
