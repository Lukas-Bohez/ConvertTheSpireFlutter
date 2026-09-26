import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:crypto/crypto.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the seeding fixes in third_party/dtorrent_task_v2 (see its
/// README): a finished torrent takes one incoming peer after another, sends
/// the blocks it is asked for, turns down requests for pieces it doesn't
/// have, keeps count of what it sent across restarts, and a small torrent
/// doesn't freeze when a peer with the fast extension connects.
void main() {
  const pieceLength = 16384;
  late Directory dir;
  late Uint8List data;
  late TorrentModel model;
  InternetAddress? localIp;
  final tasks = <TorrentTask>[];

  setUpAll(() async {
    // The task turns away connections from 127.0.0.1, so the peer here
    // connects through a real interface.
    for (final interface in await NetworkInterface.list()) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
          localIp ??= address;
        }
      }
    }
  });

  /// A finished torrent of [pieces] pieces in [dir], as [model].
  Future<void> makeTorrent(int pieces) async {
    final random = Random(3);
    data = Uint8List.fromList(
        List.generate(pieces * pieceLength, (_) => random.nextInt(256)));
    await File('${dir.path}/seed.bin').writeAsBytes(data);
    final hashes = BytesBuilder();
    for (var i = 0; i < pieces; i++) {
      hashes.add(sha1
          .convert(data.sublist(i * pieceLength, (i + 1) * pieceLength))
          .bytes);
    }
    final info = encode({
      'length': data.length,
      'name': 'seed.bin',
      'piece length': pieceLength,
      'pieces': hashes.toBytes(),
    });
    final torrentFile = File('${dir.path}/seed.torrent');
    await torrentFile.writeAsBytes(encode({'info': decode(info)}));
    final parsed = await TorrentModel.parse(torrentFile.path);
    // As the app does: the hash of the info dictionary's own bytes.
    model = TorrentModel(
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
    // Tell it the data is all there.
    final state = await StateFileV2.getStateFile('${dir.path}/', model);
    for (var i = 0; i < pieces; i++) {
      await state.updateBitfield(i);
    }
    await state.close();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seeding_test');
    // More pieces than the 10 of the fast extension's allowed set.
    await makeTorrent(12);
  });

  tearDown(() async {
    for (final task in tasks) {
      await task.stop();
    }
    tasks.clear();
    await dir.delete(recursive: true);
  });

  Future<(TorrentTask, int)> startTask() async {
    final task = TorrentTask.newTask(model, '${dir.path}/', false);
    tasks.add(task);
    final started = await task.start();
    return (task, started['tcp_socket'] as int);
  }

  test('takes one incoming peer after another', () async {
    if (localIp == null) {
      markTestSkipped('no network interface besides loopback');
      return;
    }
    final (_, port) = await startTask();
    for (var round = 0; round < 3; round++) {
      final peer = await _Peer.connect(localIp!, port, model.infoHashBuffer);
      // The first peer used to be the only one: the task checked its own
      // address, the same for every connection, and never let go of it.
      expect(await peer.handshake, isTrue, reason: 'peer ${round + 1}');
      await peer.close();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  });

  test(
      'sends the blocks asked for, turns down pieces it lacks, and keeps '
      'count of what it sent across restarts', () async {
    if (localIp == null) {
      markTestSkipped('no network interface besides loopback');
      return;
    }
    var (task, port) = await startTask();
    final peer = await _Peer.connect(localIp!, port, model.infoHashBuffer);
    expect(await peer.handshake, isTrue);
    peer.send(2); // interested
    await peer.next(1); // unchoke

    peer.request(1, 0, pieceLength);
    final piece = await peer.next(7);
    expect(piece.sublist(8), data.sublist(pieceLength, 2 * pieceLength));

    // A piece index past the end made the read throw, and the request
    // stayed queued for good.
    peer.request(99, 0, pieceLength);
    final rejected = await peer.next(16);
    expect(ByteData.sublistView(rejected).getUint32(0), 99);

    expect(task.uploaded, pieceLength);
    await peer.close();
    await task.stop();
    tasks.remove(task);

    // Each start used to count from zero and replace the stored total.
    (task, port) = await startTask();
    expect(task.uploaded, pieceLength);
  });

  test('a small torrent answers a peer with the fast extension', () async {
    if (localIp == null) {
      markTestSkipped('no network interface besides loopback');
      return;
    }
    // Fewer pieces than the allowed fast set: choosing them never ended, and
    // the app froze at full CPU on this peer's handshake.
    await dir.delete(recursive: true);
    dir = await Directory.systemTemp.createTemp('seeding_test');
    await makeTorrent(3);
    final (_, port) = await startTask();
    final peer = await _Peer.connect(localIp!, port, model.infoHashBuffer);
    expect(await peer.handshake, isTrue);
    final allowed = {
      for (var i = 0; i < 3; i++)
        ByteData.sublistView(await peer.next(17)).getUint32(0),
    };
    expect(allowed, {0, 1, 2});
    await peer.close();
  });
}

/// A peer that speaks just enough of the protocol, with the fast extension.
class _Peer {
  _Peer._(this._socket, this._infoHash) {
    _socket.listen(_onData, onDone: _onDone, onError: (_) => _onDone());
    final reserved = Uint8List(8)..[7] = 0x04;
    _socket.add([
      19,
      ...'BitTorrent protocol'.codeUnits,
      ...reserved,
      ..._infoHash,
      ...'-TT0001-abcdefghijkl'.codeUnits,
    ]);
  }

  static Future<_Peer> connect(
      InternetAddress address, int port, Uint8List infoHash) async {
    final socket = await Socket.connect(address, port,
        sourceAddress: address, timeout: const Duration(seconds: 5));
    return _Peer._(socket, infoHash);
  }

  final Socket _socket;
  final Uint8List _infoHash;
  final _buffer = BytesBuilder();
  final _handshake = Completer<bool>();
  final _messages = <(int, Uint8List)>[];
  Completer<void>? _arrived;
  bool _closed = false;

  /// Whether the task answered with its own handshake for this torrent.
  Future<bool> get handshake =>
      _handshake.future.timeout(const Duration(seconds: 5));

  void send(int id, [List<int> payload = const []]) {
    final message = ByteData(5)
      ..setUint32(0, payload.length + 1)
      ..setUint8(4, id);
    _socket.add([...message.buffer.asUint8List(), ...payload]);
  }

  void request(int index, int begin, int length) {
    final payload = ByteData(12)
      ..setUint32(0, index)
      ..setUint32(4, begin)
      ..setUint32(8, length);
    send(6, payload.buffer.asUint8List());
  }

  /// The payload of the next message [id], skipping others.
  Future<Uint8List> next(int id) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final i = _messages.indexWhere((m) => m.$1 == id);
      if (i != -1) return _messages.removeAt(i).$2;
      if (_closed) throw StateError('closed before message $id');
      final wait = deadline.difference(DateTime.now());
      if (wait.isNegative) throw TimeoutException('no message $id');
      _arrived = Completer<void>();
      await _arrived!.future.timeout(wait, onTimeout: () {});
    }
  }

  Future<void> close() async {
    await _socket.close();
    _socket.destroy();
  }

  void _onData(Uint8List bytes) {
    _buffer.add(bytes);
    var all = _buffer.toBytes();
    var offset = 0;
    if (!_handshake.isCompleted) {
      if (all.length < 68) return;
      var same = all[0] == 19;
      for (var i = 0; i < 20 && same; i++) {
        same = all[28 + i] == _infoHash[i];
      }
      _handshake.complete(same);
      offset = 68;
    }
    while (all.length - offset >= 4) {
      final length = ByteData.sublistView(all, offset).getUint32(0);
      if (all.length - offset - 4 < length) break;
      if (length > 0) {
        _messages.add((
          all[offset + 4],
          Uint8List.fromList(all.sublist(offset + 5, offset + 4 + length)),
        ));
      }
      offset += 4 + length;
    }
    _buffer
      ..clear()
      ..add(all.sublist(offset));
    _arrived?.complete();
    _arrived = null;
  }

  void _onDone() {
    _closed = true;
    if (!_handshake.isCompleted) _handshake.complete(false);
    _arrived?.complete();
    _arrived = null;
  }
}
