import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:dtorrent_task_v2/src/file/download_file_requests.dart';
import 'package:dtorrent_task_v2/src/file/utils.dart';
import 'package:dtorrent_task_v2/src/piece/piece_base.dart';
import 'package:logging/logging.dart';

var _log = Logger("DownloadFile");

class DownloadFile {
  // This is the full path of the local file
  final String filePath;

  // This is the path inside the torrent info dictionary
  final String torrentFilePath;

  // This is the name inside the torrent info dictionary
  String get originalFileName =>
      torrentFilePath.split(Platform.pathSeparator).last;

// the offset of the file from the start of the torrent block
  final int offset;

  final int length;

  // the offseted end position relative to the torrent block
  int get end => offset + length;

  int downloadedBytes = 0;
  List<Piece> pieces;

  bool get completelyFlushed => pieces.none((element) => !element.flushed);
  bool get completed => downloadedBytes == length;
  double get downloadProgress => downloadedBytes / length * 100;

  File? _file;

  RandomAccessFile? _writeAccess;

  RandomAccessFile? _readAccess;

  StreamController<FileRequest>? _streamController;

  StreamController<List<int>> _hlsStreamController = StreamController();

  StreamSubscription? _bytesRequestSubscription;
  StreamController _bytesRequestController = StreamController();

  int _streamEndPosition = 0;
  int _streamPosition = 0;
  int get _streamLengthLeft => _streamEndPosition - _streamPosition;
  StreamSubscription<FileRequest>? _streamSubscription;

  DownloadFile(
    this.filePath,
    this.offset,
    this.length,
    this.torrentFilePath,
    this.pieces,
  ) {
    for (var piece in pieces) {
      if (piece.isCompletelyWritten) {
        var blockPosition = blockToDownloadFilePosition(
            piece.offset, piece.end, piece.byteLength, this);
        if (blockPosition == null) continue;
        downloadedBytes += blockPosition.blockEnd - blockPosition.blockStart;
      }
    }
  }

  bool _closed = false;

  bool get isClosed => _closed;

  /// Notify this class write the [block] (from [start] to [end]) into the downloading file ,
  /// content start position is [position]
  ///
  /// **NOTE** :
  ///
  /// Invoke this method does not mean this class should write content immediately , it will wait for other
  /// `READ`/`WRITE` which first come in the operation stack completing.
  ///
  Future<bool> requestWrite(
      int position, List<int> block, int start, int end) async {
    _writeAccess ??= await _getRandomAccessFile(FileRequestType.write);
    var completer = Completer<bool>();
    _streamController?.add(WriteRequest(
      position: position,
      start: start,
      end: end,
      block: block,
      completer: completer,
    ));

    return completer.future;
  }

  Future<List<int>> requestRead(int position, int length) async {
    _readAccess ??= await _getRandomAccessFile(FileRequestType.read);
    var completer = Completer<List<int>>();
    _streamController?.add(
        ReadRequest(completer: completer, position: position, length: length));
    return completer.future;
  }

  Stream<List<int>>? createStream(int startByte, int endByte) {
    // TODO: This algorithm doesn't work well when the moov atom is not in the start of the file
    // TODO: this currently support only one stream at a time, should it support more? how do we handle required pieces!
    _hlsStreamController.close();

    _bytesRequestSubscription?.cancel();
    _bytesRequestController.close();
    _hlsStreamController = StreamController<List<int>>();
    _streamEndPosition = endByte; //reset endposition
    _streamPosition = startByte; // reset start position
    _bytesRequestController = StreamController();
    _bytesRequestSubscription =
        _bytesRequestController.stream.listen(_processBytes);
    _bytesRequestController.add(null);
    return _hlsStreamController.stream;
  }

  ///
  ///
  /// the input should be offseted
  ///
  /// the output will be offseted
  ///
  int? _calculateLastDownloadedByte(int startByte) {
    var pieceLength = pieces.first.byteLength;

    var startPieceIndex = startByte ~/ pieceLength;
    var totalLastByte = startByte;
    for (var piece
        in pieces.where((element) => element.index >= startPieceIndex)) {
      var lastSubPieceByte = piece
          .calculateLastDownloadedByte(math.max(piece.offset, totalLastByte));
      totalLastByte = lastSubPieceByte;
      if (totalLastByte < piece.end) {
        break;
      }
    }
    return math.min(totalLastByte, end);
  }

  Future<void> _processBytes(dynamic _) async {
    _bytesRequestSubscription?.pause();
    await _pushBytes();
    _bytesRequestSubscription?.resume();
  }

  Future<void> _pushBytes() async {
    if (_hlsStreamController.isClosed) return;

    var lastDownloadedByte =
        _calculateLastDownloadedByte(_streamPosition + offset);
    if (lastDownloadedByte == null) return;
    var fileLastDownloadedByte = lastDownloadedByte - offset;
    //TODO: what if the file is really big? should we read a maximum smaller size?
    var lengthToRead =
        math.min(fileLastDownloadedByte, _streamEndPosition) - _streamPosition;

    await _readAndPushBytes(
      _streamPosition,
      lengthToRead,
    );
  }

  Future<void> _readAndPushBytes(
    int start,
    int lengthToRead,
  ) async {
    if (_hlsStreamController.isClosed) return;
    var bytes = await requestRead(start, lengthToRead);

    var timeStamp = DateTime.now();
    _log.fine(
        "[$timeStamp] startByte: $start, lengthToRead:$lengthToRead, downloadedBytes: $downloadedBytes");
    if (_hlsStreamController.isClosed) return;
    var leftPosition = start + bytes.length;
    _streamPosition = leftPosition;

    _hlsStreamController.add(bytes);
    // log("[$timeStamp] lengthLeft: $_streamLengthLeft");
    if (_streamLengthLeft < 1) {
      _hlsStreamController.close();
      _streamPosition = 0;
      _streamEndPosition = 0;
    }
  }

  /// Process read and write requests.
  ///
  /// Only one request is processed at a time. The Stream is paused through StreamSubscription
  /// upon entering this method, and it resumes reading from the channel only after processing
  /// the current request.
  void _processRequest(FileRequest event) async {
    _streamSubscription?.pause();
    if (event is WriteRequest) {
      await _write(event);
    }
    if (event is ReadRequest) {
      await _read(event);
    }
    if (event is FlushRequest) {
      await _flush(event);
    }
    _streamSubscription?.resume();
  }

  Future<void> _write(WriteRequest request) async {
    try {
      _writeAccess = await _getRandomAccessFile(FileRequestType.write);
      _writeAccess = await _writeAccess?.setPosition(request.position);
      _writeAccess = await _writeAccess?.writeFrom(
          request.block, request.start, request.end);
      request.completer.complete(true);
      // if there is a request pending push bytes to it
      _bytesRequestController.add(null);
      downloadedBytes += request.end - request.start;
    } catch (e) {
      _log.warning(
        'Write file error:',
        e,
      );
      request.completer.complete(false);
    }
  }

  /// Request to write the buffer to disk.
  Future<bool> requestFlush() async {
    _writeAccess ??= await _getRandomAccessFile(FileRequestType.write);
    var completer = Completer<bool>();
    _streamController?.add(FlushRequest(completer: completer));
    return completer.future;
  }

  Future<void> _flush(FlushRequest event) async {
    try {
      _writeAccess = await _getRandomAccessFile(FileRequestType.write);
      await _writeAccess?.flush();
      event.completer.complete(true);
    } catch (e) {
      _log.warning('Flush error:', e);
      event.completer.complete(false);
    }
  }

  Future<void> _read(ReadRequest request) async {
    try {
      var access = await _getRandomAccessFile(FileRequestType.read);
      access = await access.setPosition(request.position);
      var contents = await access.read(request.length);
      request.completer.complete(contents);
    } catch (e) {
      _log.warning('Read file error:', e);
      request.completer.complete(<int>[]);
    }
  }

  ///
  /// Get the corresponding file, and if the file does not exist, create a new file.
  Future<File?> _getOrCreateFile() async {
    _file ??= File(filePath);
    var exists = await _file?.exists();
    if (exists != null && !exists) {
      _file = await _file?.create(recursive: true);
      var access = await _file?.open(mode: FileMode.write);
      access = await access?.truncate(length);
      await access?.close();
    }
    return _file;
  }

  Future<bool>? get exists {
    return File(filePath).exists();
  }

  Future<RandomAccessFile> _getRandomAccessFile(FileRequestType type) async {
    var file = await _getOrCreateFile();
    RandomAccessFile? access;
    if (type == FileRequestType.write) {
      _writeAccess ??= await file?.open(mode: FileMode.writeOnlyAppend);
      access = _writeAccess;
    } else {
      _readAccess ??= await file?.open(mode: FileMode.read);
      access = _readAccess;
    }
    if (_streamController == null) {
      _streamController = StreamController();
      _streamSubscription = _streamController?.stream.listen(_processRequest);
    }
    return access!;
  }

  Future<void> close() async {
    if (isClosed) return;
    _closed = true;
    try {
      await _streamSubscription?.cancel();
      await _streamController?.close();
      await _writeAccess?.flush();
      await _writeAccess?.close();
      await _readAccess?.close();
      //  hlsStreamController can be closed by this moment via
      //  _readAndPushBytes. So, the future never completes.
      if (!_hlsStreamController.isClosed) _hlsStreamController.close();
      await _bytesRequestSubscription?.cancel();
    } catch (e) {
      _log.warning('Close file error:', e);
    } finally {
      _writeAccess = null;
      _readAccess = null;
      _streamSubscription = null;
      _streamController = null;
      _bytesRequestSubscription = null;
    }
  }

  Future<FileSystemEntity?> delete() async {
    try {
      await close();
      var temp = _file;
      _file = null;
      // here we can get a FileSystemException
      var r = await temp?.delete();
      return r;
    } catch (e) {
      _log.warning('delete() error: ', e);
    }
    return null;
  }

  @override
  bool operator ==(other) {
    if (other is DownloadFile) {
      return other.filePath == filePath;
    }
    return false;
  }

  @override
  int get hashCode => filePath.hashCode;
}
