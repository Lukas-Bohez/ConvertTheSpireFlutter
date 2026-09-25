import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:crypto/crypto.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the two fixes in third_party/dtorrent_task_v2 (see its README):
/// without them magnet links never got their file list.
void main() {
  // Two 16 KiB metadata blocks' worth of info dictionary.
  final info = encode({
    'length': 1400 * 16384,
    'name': 'test.bin',
    'piece length': 16384,
    'pieces': Uint8List.fromList(List.generate(1400 * 20, (i) => i % 251)),
  });
  final infoHash = sha1.convert(info).toString();

  late Directory cache;
  final servers = <_FakePeer>[];
  setUp(() async {
    cache = await Directory.systemTemp.createTemp('metadata_cache_test');
    MetadataDownloader.setCacheDirectory(cache.path);
  });
  tearDown(() async {
    for (final s in servers) {
      await s.close();
    }
    servers.clear();
    if (await cache.exists()) await cache.delete(recursive: true);
  });

  Future<Uint8List> fetch(List<_FakePeer> peers) async {
    final downloader = MetadataDownloader(infoHash);
    final done = Completer<Uint8List>();
    final listener = downloader.createListener()
      ..on<MetaDataDownloadComplete>((e) {
        if (!done.isCompleted) done.complete(Uint8List.fromList(e.data));
      });
    unawaited(downloader.startDownload());
    await Future<void>.delayed(const Duration(milliseconds: 200));
    for (final peer in peers) {
      downloader.addNewPeerAddress(
        CompactAddress(InternetAddress.loopbackIPv4, peer.port),
        PeerSource.manual,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    try {
      return await done.future.timeout(const Duration(seconds: 8));
    } finally {
      await listener.dispose();
      await downloader.stop();
    }
  }

  test('sends its extension handshake before asking a strict peer for '
      'metadata', () async {
    final peer = await _FakePeer.start(info);
    servers.add(peer);

    final metadata = await fetch([peer]);

    expect(sha1.convert(metadata).toString(), infoHash);
    expect(peer.rejectedEarlyRequest, isFalse);
  });

  test('a peer that hangs up does not hold up the others', () async {
    final dead = await _FakePeer.start(info, hangUpOnRequest: true);
    final good = await _FakePeer.start(info);
    servers.addAll([dead, good]);

    final watch = Stopwatch()..start();
    final metadata = await fetch([dead, good]);

    expect(sha1.convert(metadata).toString(), infoHash);
    expect(dead.hungUp, isTrue);
    // A request left with the dead peer used to wait out a 10 s timeout and
    // then go back to that same peer.
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}

/// A metadata-serving peer as strict as libtorrent: an extended message
/// before the extension handshake closes the connection.
class _FakePeer {
  _FakePeer._(this._server, this._info, this._hangUpOnRequest) {
    _server.listen(_serve);
  }

  static Future<_FakePeer> start(Uint8List info,
      {bool hangUpOnRequest = false}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return _FakePeer._(server, info, hangUpOnRequest);
  }

  final ServerSocket _server;
  final Uint8List _info;
  final bool _hangUpOnRequest;
  final _sockets = <Socket>[];
  bool rejectedEarlyRequest = false;
  bool hungUp = false;

  int get port => _server.port;

  static const _ourMetadataId = 3;

  void _serve(Socket socket) {
    _sockets.add(socket);
    final buffer = BytesBuilder();
    var handshakeDone = false;
    int? theirMetadataId;

    void send(int ext, List<int> payload) {
      final body = [20, ext, ...payload];
      socket.add([
        ...(ByteData(4)..setUint32(0, body.length)).buffer.asUint8List(),
        ...body,
      ]);
    }

    socket.listen((chunk) {
      buffer.add(chunk);
      var data = buffer.toBytes();
      if (!handshakeDone) {
        if (data.length < 68) return;
        socket.add([
          19,
          ...'BitTorrent protocol'.codeUnits,
          0, 0, 0, 0, 0, 0x10, 0, 0,
          ...data.sublist(28, 48),
          ...'-FK0001-000000000000'.codeUnits,
        ]);
        send(0, encode({
          'm': {'ut_metadata': _ourMetadataId},
          'metadata_size': _info.length,
        }));
        handshakeDone = true;
        data = data.sublist(68);
      }
      var offset = 0;
      while (data.length - offset >= 4) {
        final length =
            ByteData.sublistView(data, offset, offset + 4).getUint32(0);
        if (data.length - offset - 4 < length) break;
        final message = data.sublist(offset + 4, offset + 4 + length);
        offset += 4 + length;
        if (message.length < 2 || message[0] != 20) continue;
        final payload = message.sublist(2);
        if (message[1] == 0) {
          final m = decode(payload)['m'];
          theirMetadataId = m is Map ? m['ut_metadata'] as int? : null;
        } else if (message[1] == _ourMetadataId) {
          if (theirMetadataId == null) {
            rejectedEarlyRequest = true;
            socket.destroy();
            return;
          }
          if (_hangUpOnRequest) {
            hungUp = true;
            socket.destroy();
            return;
          }
          final piece = decode(payload)['piece'] as int;
          final start = piece * 16384;
          final end = (start + 16384).clamp(0, _info.length);
          send(theirMetadataId!, [
            ...encode({
              'msg_type': 1,
              'piece': piece,
              'total_size': _info.length,
            }),
            ..._info.sublist(start, end),
          ]);
        }
      }
      buffer.clear();
      if (offset < data.length) buffer.add(data.sublist(offset));
    }, onError: (_) {}, cancelOnError: true);
  }

  Future<void> close() async {
    for (final s in _sockets) {
      s.destroy();
    }
    await _server.close();
  }
}
