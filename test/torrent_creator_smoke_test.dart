import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:convert_the_spire_reborn/src/vault/bittorrent/torrent_file.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_creator_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates and parses a small torrent', () async {
    final tempRoot = await Directory.systemTemp.createTemp('torrent_creator_smoke_');
    addTearDown(() async {
      await tempRoot.delete(recursive: true);
    });

    final sourceDir = Directory('${tempRoot.path}${Platform.pathSeparator}source')..createSync();
    File('${sourceDir.path}${Platform.pathSeparator}a.txt').writeAsStringSync('hello');
    File('${sourceDir.path}${Platform.pathSeparator}b.txt').writeAsStringSync('world!');

    final outputDir = Directory('${tempRoot.path}${Platform.pathSeparator}output')..createSync();

    final entries = await TorrentCreatorService.instance.collectEntries(
      filePaths: const [],
      directoryPaths: [sourceDir.path],
    );

    final result = await TorrentCreatorService.instance.createTorrent(
      entries: entries,
      torrentName: 'Tiny Sample',
      trackers: const ['udp://tracker.opentrackr.org:1337/announce'],
      isPrivate: false,
      outputDirectory: outputDir.path,
      comment: 'smoke test',
      selectedPieceSize: 16,
    );

    final torrentBytes = await File(result.torrentPath).readAsBytes();
    final metadata = TorrentFileParser.parse(torrentBytes);

    expect(await File(result.torrentPath).exists(), isTrue);
    expect(metadata.name, 'Tiny Sample');
    expect(metadata.files.length, 2);
    expect(metadata.trackers, contains('udp://tracker.opentrackr.org:1337/announce'));
    expect(metadata.pieceLength, 16);
    expect(metadata.pieceHashes, isNotEmpty);
  });
}
