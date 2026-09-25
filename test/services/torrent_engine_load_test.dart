import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/receive_buffer.dart';
import 'package:dtorrent_task_v2/src/piece/piece_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the changes in third_party/dtorrent_task_v2 that keep a download
/// from freezing the app (see its README): the peer receive buffer, piece
/// hashing on a background isolate, and the state file written in one go
/// instead of after every piece.
void main() {
  group('ReceiveBuffer', () {
    test('keeps bytes in order across adds, takes and growth', () {
      final buffer = ReceiveBuffer();
      final expected = <int>[];
      final random = Random(1);
      var next = 0;
      for (var round = 0; round < 400; round++) {
        final chunk = Uint8List(random.nextInt(70000));
        for (var i = 0; i < chunk.length; i++) {
          chunk[i] = next++ & 0xff;
        }
        buffer.add(chunk);
        expected.addAll(chunk);
        expect(buffer.length, expected.length);

        final take = random.nextInt(buffer.length + 1);
        expect(buffer.view.sublist(0, take), expected.sublist(0, take));
        buffer.consume(take);
        expected.removeRange(0, take);
        if (expected.isNotEmpty) {
          expect(buffer[0], expected.first);
          expect(buffer[expected.length - 1], expected.last);
        }
      }
      expect(buffer.view, expected);
    });

    test('moves unread bytes to the front when they overlap', () {
      final buffer = ReceiveBuffer()
        ..add(Uint8List.fromList(List.generate(60000, (i) => i & 0xff)));
      buffer.consume(10000);
      // 50000 unread bytes move to the front of the same storage.
      buffer.add(Uint8List(20000));
      expect(buffer.length, 70000);
      expect(buffer.view.sublist(0, 50000),
          List.generate(50000, (i) => (i + 10000) & 0xff));
    });

    test('rejects reads and takes past the end', () {
      final buffer = ReceiveBuffer()..add(Uint8List(4));
      expect(() => buffer[4], throwsRangeError);
      expect(() => buffer.consume(5), throwsRangeError);
      buffer.clear();
      expect(buffer.isEmpty, isTrue);
    });
  });

  group('PieceHasher', () {
    test('matches SHA-1 and SHA-256 computed here', () async {
      final random = Random(2);
      final pieces = [
        for (final size in [0, 1, 16384, 1 << 20, 1234567])
          Uint8List.fromList(List.generate(size, (_) => random.nextInt(256))),
      ];
      final sha1s = await Future.wait(pieces.map(PieceHasher.instance.sha1));
      final sha256s =
          await Future.wait(pieces.map(PieceHasher.instance.sha256));
      for (var i = 0; i < pieces.length; i++) {
        expect(sha1s[i], sha1.convert(pieces[i]).bytes);
        expect(sha256s[i], sha256.convert(pieces[i]).bytes);
      }
    });

    test('hashes only the bytes a view shows', () async {
      final whole = Uint8List.fromList(List.generate(1000, (i) => i & 0xff));
      final view = Uint8List.sublistView(whole, 100, 600);
      expect(await PieceHasher.instance.sha1(view),
          sha1.convert(whole.sublist(100, 600)).bytes);
    });
  });

  group('StateFileV2', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('state_file_test');
    });
    tearDown(() => dir.delete(recursive: true));

    TorrentModel model(int pieces) => TorrentModel(
          name: 'test.bin',
          files: const [],
          infoHashBuffer: Uint8List.fromList(List.generate(20, (i) => i + 1)),
          pieceLength: 16384,
          pieces: List.generate(pieces, (_) => Uint8List(20)),
          announces: const [],
          nodes: const [],
          length: pieces * 16384 - 100,
          version: TorrentVersion.v1,
        );

    /// The storage flags byte of the header: 1 compressed, 2 sparse.
    Future<int> storedAs(TorrentModel torrent) async {
      final bytes =
          await File('${dir.path}/${torrent.infoHash}.bt.state').readAsBytes();
      return bytes[64];
    }

    Future<void> roundTrip(
        int pieces, Iterable<int> complete, int flags) async {
      final torrent = model(pieces);
      final state = await StateFileV2.getStateFile('${dir.path}/', torrent);
      for (final i in complete) {
        expect(await state.updateBitfield(i), isTrue);
      }
      expect(await state.updateBitfield(complete.first), isFalse);
      await state.updateUploaded(123456);
      // The changes are here at once...
      for (final i in complete) {
        expect(state.bitfield.getBit(i), isTrue);
      }
      // ...and in the file once it is closed.
      await state.close();
      expect(await storedAs(torrent), flags);

      final loaded = await StateFileV2.getStateFile('${dir.path}/', torrent);
      expect(await loaded.validate(), isTrue);
      expect(loaded.isValid, isTrue);
      expect(loaded.uploaded, 123456);
      expect(loaded.bitfield.completedPieces.toSet(), complete.toSet());
      await loaded.close();
    }

    test('few pieces complete: stored sparse', () {
      return roundTrip(100, [3, 70, 9], 2);
    });

    test('many pieces complete: stored whole', () {
      return roundTrip(100, List.generate(60, (i) => i * 3 ~/ 2), 0);
    });

    test('a large bitfield: stored compressed', () {
      return roundTrip(20000, List.generate(12000, (i) => i), 1);
    });

    test('changes reach the file without closing it', () async {
      final torrent = model(100);
      final state = await StateFileV2.getStateFile('${dir.path}/', torrent);
      for (var i = 0; i < 50; i++) {
        await state.updateBitfield(i);
      }
      await Future<void>.delayed(
          StateFileV2.saveDelay + const Duration(milliseconds: 500));
      final copy = await StateFileV2.getStateFile('${dir.path}/', torrent);
      expect(copy.bitfield.completedPieces.length, 50);
      expect(await copy.validate(), isTrue);
      await state.close();
      await copy.close();
    });
  });
}
