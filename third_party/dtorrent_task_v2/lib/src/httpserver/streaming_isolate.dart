import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/torrent/torrent_file_model.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';

var _log = Logger('StreamingIsolate');

/// Messages sent to the streaming isolate
abstract class StreamingIsolateMessage {}

/// Request to get playlist data
class GetPlaylistMessage implements StreamingIsolateMessage {
  final List<TorrentFileModel> files;
  final InternetAddress address;
  final int port;

  GetPlaylistMessage(this.files, this.address, this.port);
}

/// Request to get JSON metadata
class GetJsonMetadataMessage implements StreamingIsolateMessage {
  final List<TorrentFileModel> files;
  final int totalLength;
  final int downloaded;
  final double downloadSpeed;
  final double uploadSpeed;
  final int totalPeers;
  final int activePeers;

  GetJsonMetadataMessage(
    this.files,
    this.totalLength,
    this.downloaded,
    this.downloadSpeed,
    this.uploadSpeed,
    this.totalPeers,
    this.activePeers,
  );
}

/// Response from isolate
abstract class StreamingIsolateResponse {}

class PlaylistResponse implements StreamingIsolateResponse {
  final Uint8List data;
  PlaylistResponse(this.data);
}

class JsonMetadataResponse implements StreamingIsolateResponse {
  final Uint8List data;
  JsonMetadataResponse(this.data);
}

/// Streaming isolate entry point
void _streamingIsolateEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is GetPlaylistMessage) {
      try {
        final playlist =
            _createPlaylist(message.files, message.address, message.port);
        sendPort.send(PlaylistResponse(Uint8List.fromList(playlist.codeUnits)));
      } catch (e, stackTrace) {
        _log.warning('Error creating playlist in isolate', e, stackTrace);
        sendPort.send(PlaylistResponse(Uint8List(0)));
      }
    } else if (message is GetJsonMetadataMessage) {
      try {
        final json = _createJsonMetadata(
          message.files,
          message.totalLength,
          message.downloaded,
          message.downloadSpeed,
          message.uploadSpeed,
          message.totalPeers,
          message.activePeers,
        );
        sendPort.send(JsonMetadataResponse(Uint8List.fromList(json.codeUnits)));
      } catch (e, stackTrace) {
        _log.warning('Error creating JSON metadata in isolate', e, stackTrace);
        sendPort.send(JsonMetadataResponse(Uint8List(0)));
      }
    }
  });
}

String _createPlaylist(
    List<TorrentFileModel> files, InternetAddress address, int port) {
  final videoFiles = files.where((element) {
    final mimeType = lookupMimeType(element.name);
    return mimeType?.startsWith('video') ??
        mimeType?.startsWith('audio') ??
        false;
  });

  final entries = videoFiles.map((file) =>
      '#EXTINF:-1,${file.path}\nhttp://${address.host}:$port/${file.path}');
  return '#EXTM3U\n${entries.join('\n')}';
}

String _createJsonMetadata(
  List<TorrentFileModel> files,
  int totalLength,
  int downloaded,
  double downloadSpeed,
  double uploadSpeed,
  int totalPeers,
  int activePeers,
) {
  final jsonEntries = files
      .map((file) => {
            'name': file.name,
            'url': 'http://localhost:9090/${file.path}',
            'length': file.length
          })
      .toList();

  final json = {
    'totalLength': totalLength,
    'downloaded': downloaded,
    'downloadSpeed': downloadSpeed,
    'uploadSpeed': uploadSpeed,
    'totalPeers': totalPeers,
    'activePeers': activePeers,
    'files': jsonEntries,
  };

  return const JsonEncoder.withIndent('  ').convert(json);
}

/// Manager for streaming isolate
class StreamingIsolateManager {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _streamingIsolateEntry,
      _receivePort!.sendPort,
      debugName: 'StreamingIsolate',
    );

    _sendPort = await _receivePort!.first as SendPort;
    _initialized = true;
    _log.info('Streaming isolate initialized');
  }

  Future<Uint8List> getPlaylist(
    List<TorrentFileModel> files,
    InternetAddress address,
    int port,
  ) async {
    if (!_initialized) await initialize();

    final completer = Completer<Uint8List>();
    late StreamSubscription subscription;

    subscription = _receivePort!.listen((response) {
      if (response is PlaylistResponse) {
        subscription.cancel();
        completer.complete(response.data);
      }
    });

    _sendPort!.send(GetPlaylistMessage(files, address, port));

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        subscription.cancel();
        _log.warning('Playlist request timeout');
        return Uint8List(0);
      },
    );
  }

  Future<Uint8List> getJsonMetadata(
    List<TorrentFileModel> files,
    int totalLength,
    int downloaded,
    double downloadSpeed,
    double uploadSpeed,
    int totalPeers,
    int activePeers,
  ) async {
    if (!_initialized) await initialize();

    final completer = Completer<Uint8List>();
    late StreamSubscription subscription;

    subscription = _receivePort!.listen((response) {
      if (response is JsonMetadataResponse) {
        subscription.cancel();
        completer.complete(response.data);
      }
    });

    _sendPort!.send(GetJsonMetadataMessage(
      files,
      totalLength,
      downloaded,
      downloadSpeed,
      uploadSpeed,
      totalPeers,
      activePeers,
    ));

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        subscription.cancel();
        _log.warning('JSON metadata request timeout');
        return Uint8List(0);
      },
    );
  }

  Future<void> dispose() async {
    if (!_initialized) return;

    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _isolate = null;
    _sendPort = null;
    _receivePort = null;
    _initialized = false;
    _log.info('Streaming isolate disposed');
  }
}
