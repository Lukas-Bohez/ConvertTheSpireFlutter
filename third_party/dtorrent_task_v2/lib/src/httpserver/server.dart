import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';

import 'streaming_isolate.dart';

class Range {
  int start;
  int end;
  Range(this.start, this.end);

  @override
  String toString() => 'Range(start: $start, end: $end)';

  Map<String, dynamic> toMap() {
    return {
      'start': start,
      'end': end,
    };
  }

  String toJson() => json.encode(toMap());
}

class RangeParser {
  final ranges = <Range>[];
  String type = 'bytes';

  RangeParser(String rangeString, int fileLength) {
    var rangeStringList = rangeString.split('=');
    String rangesStr;
    if (rangeStringList.length > 1) {
      type = rangeStringList[0].trim();
      rangesStr = rangeStringList[1].trim();
    } else {
      rangesStr = rangeStringList[0].trim();
    }
    var parseRanges = rangesStr.split(',').map((r) => r.trim());

    for (var range in parseRanges) {
      var tmp = range.split('-');
      var start = int.tryParse(tmp[0]);
      var end = int.tryParse(tmp[1]) ?? fileLength - 1;
      var tmpRange = Range(start ?? fileLength - end, end);
      ranges.add(tmpRange);
    }
  }
}

Stream<T> streamDelayer<T>(Stream<T> inputStream, Duration delay) async* {
  await for (final val in inputStream) {
    yield val;
    await Future.delayed(delay);
  }
}

var _log = Logger('StreamingServer');

class StreamingServer {
  final DownloadFileManager _fileManager;
  HttpServer? _server;
  final TorrentTask _torrentTask;
  StreamSubscription<HttpRequest>? _streamSubscription;
  InternetAddress address = InternetAddress.anyIPv4;
  int port;
  bool running = false;
  final StreamingIsolateManager _isolateManager = StreamingIsolateManager();

  StreamingServer(
    this._fileManager,
    this._torrentTask, {
    InternetAddress? address,
    this.port = 9090,
  }) : address = address ?? InternetAddress.anyIPv4;

  int getPiece(int position) {
    var pieceIndex = position ~/ _fileManager.metainfo.pieceLength;
    return pieceIndex;
  }

  String toPlaylistEntry(TorrentFileModel file) {
    return '#EXTINF:-1,${file.path}\nhttp://${address.host}:$port/${file.path}';
  }

  Map<String, dynamic> toJsonEntry(TorrentFileModel file) {
    return {
      'name': file.name,
      'url': 'http://${address.host}:$port/${file.path}',
      'length': file.length
    };
  }

  String toPlaylist(Iterable<TorrentFileModel> files) {
    return '#EXTM3U\n${files.map(toPlaylistEntry).join('\n')}';
  }

  Map<String, dynamic> toJson(List<TorrentFileModel> files) {
    return {
      'totalLength':
          _fileManager.metainfo.length ?? _fileManager.metainfo.totalSize,
      'downloaded': _fileManager.downloaded,
      // 'uploaded':_fileManager.uploaded,
      'downloadSpeed': _torrentTask.averageDownloadSpeed,
      'uploadSpeed': _torrentTask.averageUploadSpeed,
      'totalPeers': _torrentTask.allPeersNumber,
      'activePeers': _torrentTask.activePeers?.length ?? 0,
      'files': files.map(toJsonEntry).toList()
    };
  }

  Future<void> requestProcessor(HttpRequest request) async {
    // Allow CORS requests to specify arbitrary headers, e.g. 'Range',
    // by responding to the OPTIONS preflight request with the specified
    // origin and requested headers.
    if (request.method == 'OPTIONS' &&
        request.headers['access-control-request-headers'] != null) {
      if (request.headers['origin'] != null &&
          request.headers['origin']!.isNotEmpty) {
        request.response.headers
            .add('Access-Control-Allow-Origin', request.headers['origin']![0]);
      }
      request.response.headers
          .add('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
      if (request.response.headers['access-control-request-headers'] != null &&
          request
              .response.headers['access-control-request-headers']!.isNotEmpty) {
        request.response.headers.add('Access-Control-Allow-Headers',
            request.response.headers['access-control-request-headers']![0]);
      }
      request.response.headers.add('Access-Control-Max-Age', '1728000');

      request.response.close();
      return;
    }
    if (request.uri.path == "/.m3u" || request.uri.path == "/") {
      // Process playlist request in isolate to reduce main isolate load
      var buffer = await _isolateManager.getPlaylist(
        _fileManager.metainfo.files,
        address,
        port,
      );

      request.response.headers.contentType =
          ContentType.parse('application/x-mpegurl; charset=utf-8');
      request.response.contentLength = buffer.length;
      request.response.add(buffer);
      await request.response.close();
      return;
    }
    if (request.uri.path == "/.json") {
      // Process JSON metadata request in isolate to reduce main isolate load
      var buffer = await _isolateManager.getJsonMetadata(
        _fileManager.metainfo.files,
        _fileManager.metainfo.length ?? _fileManager.metainfo.totalSize,
        _fileManager.downloaded,
        _torrentTask.averageDownloadSpeed,
        _torrentTask.averageUploadSpeed,
        _torrentTask.allPeersNumber,
        _torrentTask.activePeers?.length ?? 0,
      );

      request.response.headers.contentType =
          ContentType.parse('application/json; charset=utf-8');
      request.response.contentLength = buffer.length;
      request.response.add(buffer);
      await request.response.close();
      return;
    }
    // the client can request a specific file
    var requestedFilePath = Uri.decodeComponent(request.uri.path);
    requestedFilePath = requestedFilePath.substring(1);
    var file = _fileManager.metainfo.files
        .firstWhereOrNull((element) => element.path == requestedFilePath);
    // if not, select the first file that
    file ??= _fileManager.metainfo.files.firstWhereOrNull((element) =>
        lookupMimeType(element.name)?.startsWith('video') ?? false);
    if (file == null) return;
    var range = request.headers['range'];
    RangeParser? ranges;
    if (range != null) {
      ranges = RangeParser(range[0], file.length);
    }

    Stream<List<int>>? bytes;
    int startPosition = ranges?.ranges.first.start ?? 0;
    int endPosition =
        ranges != null ? ranges.ranges.first.end + 1 : file.length;
    if (startPosition >= file.length) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.close();
      return;
    }
    if (request.method == 'HEAD') return request.response.close();
    request.response.headers.add('Accept-Ranges', 'bytes');
    request.response.headers.add('Connection', 'keep-alive');
    request.response.headers.add('Keep-Alive', 'timeout=5');
    request.response.headers.add('transferMode.dlna.org', 'Streaming');
    request.response.headers.add('contentFeatures.dlna.org',
        'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000');
    var mime = lookupMimeType(file.name);
    if (mime != null) {
      request.response.headers.contentType = ContentType.parse(mime);
    }
    request.response.headers.contentLength = endPosition - startPosition;
    if (ranges != null && ranges.ranges.isNotEmpty) {
      request.response.statusCode = 206;
      request.response.headers.add('Content-Range',
          'bytes ${ranges.ranges[0].start}-${ranges.ranges[0].end}/${file.length}');
    }
    bytes = _torrentTask.createStream(
        filePosition: startPosition,
        endPosition: endPosition,
        fileName: file.name);

    if (bytes != null) {
      try {
        await request.response.addStream(bytes).then((value) async {
          _log.fine('stream finished');
          await request.response.close();
        });
      } catch (e) {
        _log.fine(
          'streamed data did not finish',
        );
      }
    }
    request.response.close();
  }

  Future<StreamingServerStarted> start() async {
    _server = await HttpServer.bind(address, port);
    _streamSubscription = _server?.listen(requestProcessor);
    running = true;
    return StreamingServerStarted(port: port, internetAddress: address);
  }

  Future<void> stop() async {
    running = false;
    await _server?.close();
    await _streamSubscription?.cancel();
    await _isolateManager.dispose();
  }
}
