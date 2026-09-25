import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:logging/logging.dart';

var _log = Logger('PieceHasher');

const _sha1 = 0;
const _sha256 = 1;

/// Hashes pieces on a background isolate.
///
/// Every downloaded piece used to be hashed on the isolate running the
/// download, which in an app is its UI isolate: a slow CPU takes half a
/// second over the SHA-1 of a 16 MB piece, and the app froze for that long
/// on every piece. The worker isolate starts on the first hash; where it
/// can't start, pieces are hashed here as before.
class PieceHasher {
  PieceHasher._();

  static final PieceHasher instance = PieceHasher._();

  RawReceivePort? _replies;
  SendPort? _worker;
  bool _unavailable = false;
  final Map<int, _Request> _pending = {};
  final List<int> _unsent = [];
  var _nextId = 0;

  /// The SHA-1 digest of [data].
  Future<Uint8List> sha1(Uint8List data) => _hash(_sha1, data);

  /// The SHA-256 digest of [data].
  Future<Uint8List> sha256(Uint8List data) => _hash(_sha256, data);

  Future<Uint8List> _hash(int algorithm, Uint8List data) {
    if (_unavailable) return Future.value(_digest(algorithm, data));
    final id = _nextId++;
    final request = _Request(algorithm, data);
    _pending[id] = request;
    _replies ??= _start();
    // Only waiting hashes keep the program running.
    _replies!.keepIsolateAlive = true;
    final worker = _worker;
    if (worker == null) {
      _unsent.add(id);
    } else {
      worker.send(request.message(id));
    }
    return request.completer.future;
  }

  RawReceivePort _start() {
    final replies = RawReceivePort(_onMessage, 'PieceHasher replies');
    Isolate.spawn(_work, replies.sendPort,
            debugName: 'PieceHasher',
            onExit: replies.sendPort,
            onError: replies.sendPort)
        .catchError((Object e) {
      _log.warning('Hashing on a background isolate failed to start', e);
      _stop();
      return Isolate.current;
    });
    return replies;
  }

  void _onMessage(Object? message) {
    if (message is SendPort) {
      _worker = message;
      for (final id in _unsent) {
        final request = _pending[id];
        if (request != null) message.send(request.message(id));
      }
      _unsent.clear();
      return;
    }
    if (message is List && message.length == 2 && message[0] is int) {
      final request = _pending.remove(message[0]);
      request?.completer.complete(message[1] as Uint8List);
      if (_pending.isEmpty) _replies?.keepIsolateAlive = false;
      return;
    }
    // An error in the worker ([message] is its error and stack trace) or
    // its exit (null).
    _log.warning('Hashing isolate stopped: $message');
    _stop();
  }

  /// Hashes what is still waiting here, and everything after it.
  void _stop() {
    _unavailable = true;
    _replies?.close();
    _replies = null;
    _worker = null;
    _unsent.clear();
    final waiting = Map.of(_pending);
    _pending.clear();
    waiting.forEach((_, request) {
      request.completer.complete(_digest(request.algorithm, request.data));
    });
  }
}

class _Request {
  final int algorithm;
  final Uint8List data;
  final completer = Completer<Uint8List>();

  _Request(this.algorithm, this.data);

  /// The request for the worker. A view is sent as a copy of the bytes it
  /// shows, not with the whole buffer behind it.
  List<Object> message(int id) {
    final whole = data.offsetInBytes == 0 &&
        data.lengthInBytes == data.buffer.lengthInBytes;
    return [id, algorithm, whole ? data : Uint8List.fromList(data)];
  }
}

Uint8List _digest(int algorithm, Uint8List data) {
  final hash = algorithm == _sha256 ? crypto.sha256 : crypto.sha1;
  return Uint8List.fromList(hash.convert(data).bytes);
}

void _work(SendPort replies) {
  final requests = RawReceivePort((Object? message) {
    final request = message as List;
    replies.send(
        [request[0], _digest(request[1] as int, request[2] as Uint8List)]);
  }, 'PieceHasher requests');
  replies.send(requests.sendPort);
}
