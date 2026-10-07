import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:crypto/crypto.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:flutter_test/flutter_test.dart';

/// A finished torrent file is not kept locked while it seeds (issue #41).
/// On Windows a program can't be started while another program has it open
/// for writing, and no file can be moved or deleted while it is open at all.
void main() {
  const pieceLength = 16384;
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('file_lock_test');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  /// [data] downloaded into [path] the way a task does it: every piece handed
  /// over and its blocks written at once, then flushed.
  Future<DownloadFile> download(Uint8List data, String path) async {
    final count = (data.length + pieceLength - 1) ~/ pieceLength;
    final pieces = [
      for (var i = 0; i < count; i++)
        Piece('', i, min(pieceLength, data.length - i * pieceLength),
            i * pieceLength),
    ];
    final file = DownloadFile(path, 0, data.length, 'file', pieces);
    for (final piece in pieces) {
      piece.init();
      piece.flush();
    }
    final written = await Future.wait([
      for (final piece in pieces)
        file.requestWrite(piece.offset, data, piece.offset, piece.end),
    ]);
    expect(written, everyElement(isTrue));
    expect(await file.requestFlush(), isTrue);
    return file;
  }

  test('a program downloaded from a peer starts while it seeds', () async {
    InternetAddress? localIp;
    // The task turns away connections from 127.0.0.1, so the peers connect
    // through a real interface.
    for (final interface in await NetworkInterface.list()) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
          localIp ??= address;
        }
      }
    }
    if (localIp == null) {
      markTestSkipped('no network interface besides loopback');
      return;
    }

    final program =
        await File(r'C:\Windows\System32\hostname.exe').readAsBytes();
    final seeder = await Directory('${dir.path}/seeder').create();
    final leecher = await Directory('${dir.path}/leecher').create();
    await File('${seeder.path}/hostname.exe').writeAsBytes(program);
    final count = (program.length + pieceLength - 1) ~/ pieceLength;
    final hashes = BytesBuilder();
    for (var i = 0; i < count; i++) {
      hashes.add(sha1
          .convert(program.sublist(
              i * pieceLength, min((i + 1) * pieceLength, program.length)))
          .bytes);
    }
    final info = encode({
      'length': program.length,
      'name': 'hostname.exe',
      'piece length': pieceLength,
      'pieces': hashes.toBytes(),
    });
    final torrentFile = File('${dir.path}/hostname.torrent');
    await torrentFile.writeAsBytes(encode({'info': decode(info)}));
    final parsed = await TorrentModel.parse(torrentFile.path);
    final model = TorrentModel(
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
    final state = await StateFileV2.getStateFile('${seeder.path}/', model);
    for (var i = 0; i < count; i++) {
      await state.updateBitfield(i);
    }
    await state.close();

    final seeding = TorrentTask.newTask(model, '${seeder.path}/', false);
    final downloading = TorrentTask.newTask(model, '${leecher.path}/', false);
    addTearDown(() async {
      await downloading.stop();
      await seeding.stop();
    });
    final port = (await seeding.start())['tcp_socket'] as int;
    final complete = Completer<void>();
    downloading.createListener().on<AllComplete>((_) {
      if (!complete.isCompleted) complete.complete();
    });
    await downloading.start();
    downloading.addPeer(CompactAddress(localIp, port), PeerSource.manual);
    await complete.future.timeout(const Duration(seconds: 30));

    final path = '${leecher.path}${Platform.pathSeparator}hostname.exe';
    expect(await File(path).readAsBytes(), program);
    // Started while the downloading task goes on seeding it.
    final result = await Process.run(path, const []);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  }, skip: !Platform.isWindows);

  test('a downloaded program starts while its torrent seeds', () async {
    final program = File(r'C:\Windows\System32\hostname.exe');
    final path = '${dir.path}${Platform.pathSeparator}hostname.exe';
    final file = await download(await program.readAsBytes(), path);

    // Started while the file is still part of a running torrent.
    final result = await Process.run(path, const []);
    expect(result.exitCode, 0, reason: '${result.stderr}');

    // A peer asking for blocks doesn't lock it either.
    expect(await file.requestRead(0, 100), hasLength(100));
    final again = await Process.run(path, const []);
    expect(again.exitCode, 0, reason: '${again.stderr}');

    await file.close();
  }, skip: !Platform.isWindows);

  test('a seeding file can be moved once no peer is reading it', () async {
    final previous = DownloadFile.readIdleTimeout;
    DownloadFile.readIdleTimeout = const Duration(milliseconds: 50);
    addTearDown(() => DownloadFile.readIdleTimeout = previous);

    final data = Uint8List.fromList(
        List.generate(5 * pieceLength + 100, (i) => i % 251));
    final path = '${dir.path}${Platform.pathSeparator}seed.bin';
    final file = await download(data, path);
    expect(await file.requestRead(pieceLength, 10),
        data.sublist(pieceLength, pieceLength + 10));

    await Future<void>.delayed(const Duration(milliseconds: 300));
    final moved = await File(path).rename('$path.moved');
    await moved.rename(path);

    // Reading again after that still works.
    expect(await file.requestRead(0, 10), data.sublist(0, 10));
    await file.close();
  });

  test('a stopped torrent leaves no file open', () async {
    final data = Uint8List.fromList(
        List.generate(8 * pieceLength, (i) => i % 241));
    final path = '${dir.path}${Platform.pathSeparator}stopped.bin';
    final file = await download(data, path);
    await Future.wait([
      for (var i = 0; i < 8; i++) file.requestRead(i * pieceLength, 10),
    ]);
    await file.close();

    await File(path).delete();
    expect(File(path).existsSync(), isFalse);
  });
}
