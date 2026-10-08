import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_existing_data.dart';
import 'package:crypto/crypto.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:flutter_test/flutter_test.dart';

/// A torrent of files already on disk (made here from them, or added again
/// for files kept) starts complete and seeds, instead of waiting at 0%,
/// "Stalled", for a download no one can serve.
void main() {
  const pieceLength = 16384;
  late Directory dir;
  late Uint8List data;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('existing_data');
    final random = Random(9);
    data = Uint8List.fromList(
        List.generate(5 * pieceLength + 777, (_) => random.nextInt(256)));
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  /// The torrent of [data] as two files in a folder named `pack`.
  Future<TorrentModel> torrent() async {
    const split = 3 * pieceLength + 100;
    final pieces = BytesBuilder();
    for (var at = 0; at < data.length; at += pieceLength) {
      pieces.add(sha1
          .convert(data.sublist(at, min(at + pieceLength, data.length)))
          .bytes);
    }
    final info = encode({
      'files': [
        {'length': split, 'path': ['a.bin']},
        {'length': data.length - split, 'path': ['b.bin']},
      ],
      'name': 'pack',
      'piece length': pieceLength,
      'pieces': pieces.toBytes(),
    });
    final file = File('${dir.path}/pack.torrent');
    await file.writeAsBytes(encode({'info': decode(info)}));
    final parsed = await TorrentModel.parse(file.path);
    return TorrentModel(
      name: parsed.name,
      files: parsed.files,
      infoHashBuffer: Uint8List.fromList(sha1.convert(info).bytes),
      pieceLength: parsed.pieceLength,
      pieces: parsed.pieces,
      announces: const [],
      nodes: const [],
      length: parsed.length,
      version: parsed.version,
    );
  }

  Future<void> writeData() async {
    const split = 3 * pieceLength + 100;
    await Directory('${dir.path}/pack').create();
    await File('${dir.path}/pack/a.bin').writeAsBytes(data.sublist(0, split));
    await File('${dir.path}/pack/b.bin').writeAsBytes(data.sublist(split));
  }

  test('files on disk: every piece found, and the task starts complete',
      () async {
    final model = await torrent();
    await writeData();
    expect(await adoptExistingTorrentData(model, dir.path), (6, 6));

    final task = TorrentTask.newTask(model, '${dir.path}/', false);
    addTearDown(task.stop);
    await task.start();
    expect(task.downloaded, data.length);
    // Checked once: next start goes by the state file.
    expect(await adoptExistingTorrentData(model, dir.path), isNull);
  });

  test('a damaged piece is left out', () async {
    final model = await torrent();
    await writeData();
    final b = File('${dir.path}/pack/b.bin');
    final bytes = await b.readAsBytes();
    bytes[10] ^= 0xff; // in piece 3
    await b.writeAsBytes(bytes);
    expect(await adoptExistingTorrentData(model, dir.path), (5, 6));
  });

  test('nothing to check without all the files at their size', () async {
    final model = await torrent();
    expect(await adoptExistingTorrentData(model, dir.path), isNull);
    await writeData();
    await File('${dir.path}/pack/b.bin').writeAsBytes([1, 2, 3]);
    expect(await adoptExistingTorrentData(model, dir.path), isNull);
  });
}
