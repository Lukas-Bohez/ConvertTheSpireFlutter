import 'dart:async';
import 'dart:io';

import 'package:dtorrent_task_v2/src/torrent/torrent_model.dart';
import 'package:dtorrent_task_v2/src/file/download_file_manager_events.dart';
import 'package:dtorrent_task_v2/src/file/utils.dart';
import 'package:dtorrent_task_v2/src/task_events.dart';
import 'package:events_emitter2/events_emitter2.dart';
import 'package:logging/logging.dart';
import '../peer/peer_base.dart';

import '../piece/piece.dart';
import 'download_file.dart';
import 'file_validator.dart';
import '../torrent/file_tree.dart';
import '../torrent/torrent_version.dart';

var _log = Logger("DownloadFileManager");

class DownloadFileManager with EventsEmittable<DownloadFileManagerEvent> {
  final TorrentModel metainfo;

  final List<DownloadFile> _files = [];

  List<DownloadFile> get files => _files;
  final List<Piece> _pieces;
  List<List<DownloadFile>?>? _piece2fileMap;
  List<List<DownloadFile>?>? get piece2fileMap => _piece2fileMap;

  final Map<String, List<Piece>> _file2pieceMap = {};
  final dynamic _stateFile; // Can be StateFile or StateFileV2

  /// TODO: File read caching
  DownloadFileManager(
    this.metainfo,
    this._stateFile,
    this._pieces,
  ) {
    _piece2fileMap = List.filled(_stateFile.bitfield.piecesNum, null);
  }

  static Future<DownloadFileManager> createFileManager(TorrentModel metainfo,
      String localDirectory, dynamic stateFile, List<Piece> pieces,
      {bool validateOnResume = false}) async {
    var manager = DownloadFileManager(metainfo, stateFile, pieces);
    await manager._init(localDirectory);

    // Validate files on resume if requested
    if (validateOnResume) {
      await manager._validateOnResume(localDirectory);
    }

    return manager;
  }

  /// Validate files on resume
  Future<void> _validateOnResume(String directory) async {
    _log.info('Validating files on resume...');
    try {
      final validator = FileValidator(metainfo, _pieces, directory);

      // Quick validation first
      final quickValid = await validator.quickValidate();
      if (!quickValid) {
        _log.warning(
            'Quick validation failed - some files may be missing or corrupted');
      }

      // Validate pieces that are marked as complete
      final completedPieces = _stateFile.bitfield.completedPieces;
      if (completedPieces.isNotEmpty) {
        _log.info('Validating ${completedPieces.length} completed pieces...');
        var invalidCount = 0;

        for (var pieceIndex in completedPieces) {
          if (pieceIndex < _pieces.length) {
            final isValid = await validator.validatePiece(pieceIndex);
            if (!isValid) {
              _log.warning(
                  'Piece $pieceIndex failed validation, marking for re-download');
              await _stateFile.updateBitfield(pieceIndex, false);
              invalidCount++;
            }
          }
        }

        if (invalidCount > 0) {
          _log.warning(
              'Found $invalidCount invalid pieces, they will be re-downloaded');
        } else {
          _log.info('All completed pieces validated successfully');
        }
      }
    } catch (e, stackTrace) {
      _log.warning('File validation on resume failed', e, stackTrace);
      // Don't fail the resume if validation fails
    }
  }

  Future<DownloadFileManager> _init(String directory) async {
    var lastChar = directory.substring(directory.length - 1);
    if (lastChar != Platform.pathSeparator) {
      directory = directory + Platform.pathSeparator;
    }
    _initFileMap(directory);
    return this;
  }

  Bitfield get localBitfield => _stateFile.bitfield;

  bool localHave(int index) {
    return _stateFile.bitfield.getBit(index);
  }

  bool get isAllComplete {
    return _stateFile.bitfield.piecesNum ==
        _stateFile.bitfield.completedPieces.length;
  }

  int get piecesNumber => _stateFile.bitfield.piecesNum;

  Future<bool> updateBitfield(int index, [bool have = true]) async {
    var updated = await _stateFile.updateBitfield(index, have);
    if (updated) events.emit(StateFileUpdated());
    return updated;
  }

  // Future<bool> updateBitfields(List<int> indices, [List<bool> haves]) {
  //   return _stateFile.updateBitfields(indices, haves);
  // }

  Future<bool> updateUpload(int uploaded) async {
    var updated = await _stateFile.updateUploaded(uploaded);
    if (updated) events.emit(StateFileUpdated());
    return updated;
  }

  int get downloaded => _stateFile.downloaded;

  /// This method appears to only write the buffer content to the disk, but in
  /// reality,every time the cache is written, it is considered that the [Piece]
  /// corresponding to [pieceIndex] has been completed. Therefore, it will
  /// remove the file's corresponding piece index from the _file2pieceMap. When
  /// all the pieces have been removed, a File Complete event will be triggered.
  Future<bool> flushFiles(Set<int> pieceIndices) async {
    var d = _stateFile.downloaded;
    var flushed = <String>{};
    for (var i = 0; i < pieceIndices.length; i++) {
      var pieceIndex = pieceIndices.elementAt(i);
      var files = _piece2fileMap?[pieceIndex];
      if (files == null || files.isEmpty) continue;
      for (var i = 0; i < files.length; i++) {
        var file = files[i];
        var pieces = _file2pieceMap[file.torrentFilePath];
        if (pieces == null) continue;
        if (flushed.add(file.filePath)) {
          await file.requestFlush();
          // Emit only once per file
          if (file.completelyFlushed) {
            events.emit(DownloadManagerFileCompleted(file));
          }
        }
      }
    }
    events.emit(StateFileUpdated());
    var msg =
        'downloaded：${d / (1024 * 1024)} mb , Progress ${((d / metainfo.length) * 10000).toInt() / 100} %';
    _log.finer(msg);
    return true;
  }

  void _initFileMap(String directory) {
    // Check if this is a v2 torrent with file tree
    final torrentVersion = TorrentVersionHelper.detectVersion(metainfo);

    if ((torrentVersion == TorrentVersion.v2 ||
            torrentVersion == TorrentVersion.hybrid) &&
        metainfo.fileTree != null) {
      // Use v2 file tree structure
      _log.info('Using v2 file tree structure');
      _initFileMapFromTree(directory, metainfo.fileTree!);
      return;
    }

    // Use v1 file structure (files array)
    for (var i = 0; i < metainfo.files.length; i++) {
      var file = metainfo.files[i];
      var startPiece = file.offset ~/ metainfo.pieceLength;
      var endPiece = file.end ~/ metainfo.pieceLength;
      if (file.end.remainder(metainfo.pieceLength) == 0) endPiece--;

      var pieces = _file2pieceMap[file.path];
      if (pieces == null) {
        pieces = <Piece>[];
        _file2pieceMap[file.path] = pieces;
      }
      var downloadFile = DownloadFile(
          directory + file.path, file.offset, file.length, file.path, pieces);

      for (var pieceIndex = startPiece; pieceIndex <= endPiece; pieceIndex++) {
        var downloadFileList = _piece2fileMap?[pieceIndex];
        if (downloadFileList == null) {
          downloadFileList = <DownloadFile>[];
          _piece2fileMap?[pieceIndex] = downloadFileList;
        }
        if (pieceIndex < _pieces.length) {
          pieces.add(_pieces[pieceIndex]);
          downloadFileList.add(downloadFile);
        }
      }

      _files.add(downloadFile);
    }
  }

  /// Initialize file map from file tree (v2 format)
  ///
  /// This method is used when file tree is available from torrent
  void _initFileMapFromTree(
      String directory, Map<String, FileTreeEntry> fileTree) {
    final files = FileTreeHelper.extractFiles(fileTree, '');
    var currentOffset = 0;

    for (var fileInfo in files) {
      // Calculate which pieces this file spans
      var startPiece = currentOffset ~/ metainfo.pieceLength;
      var fileEnd = currentOffset + fileInfo.length;
      var endPiece = fileEnd ~/ metainfo.pieceLength;
      if (fileEnd.remainder(metainfo.pieceLength) == 0) endPiece--;

      var pieces = _file2pieceMap[fileInfo.path];
      if (pieces == null) {
        pieces = <Piece>[];
        _file2pieceMap[fileInfo.path] = pieces;
      }

      var downloadFile = DownloadFile(directory + fileInfo.path, currentOffset,
          fileInfo.length, fileInfo.path, pieces);

      for (var pieceIndex = startPiece; pieceIndex <= endPiece; pieceIndex++) {
        var downloadFileList = _piece2fileMap?[pieceIndex];
        if (downloadFileList == null) {
          downloadFileList = <DownloadFile>[];
          _piece2fileMap?[pieceIndex] = downloadFileList;
        }
        if (pieceIndex < _pieces.length) {
          pieces.add(_pieces[pieceIndex]);
          downloadFileList.add(downloadFile);
        }
      }

      _files.add(downloadFile);
      currentOffset = fileEnd;
    }
  }

  Future<List<int>?> readFile(int pieceIndex, int begin, int length) async {
    var piece = _pieces[pieceIndex];

    var files = _piece2fileMap?[pieceIndex];
    var startByte = piece.offset + begin;
    var endByte = startByte + length;
    if (files == null || files.isEmpty) return null;
    var futures = <Future<List<int>>>[];
    for (var i = 0; i < files.length; i++) {
      var tempFile = files[i];

      var re =
          blockToDownloadFilePosition(startByte, endByte, length, tempFile);
      if (re == null) continue;
      futures
          .add(tempFile.requestRead(re.position, re.blockEnd - re.blockStart));
    }
    var blocks = await Future.wait(futures);
    var block = blocks.fold<List<int>>(<int>[], (previousValue, element) {
      previousValue.addAll(element);
      return previousValue;
    });

    events.emit(SubPieceReadCompleted(pieceIndex, begin, block));

    return block;
  }

  ///
  // Writes the content of a Sub Piece to the file. After completion, a sub piece complete event will be sent.
  /// If it fails, a sub piece failed event will be sent.
  ///
  /// The Sub Piece is from the Piece corresponding to [pieceIndex], and the content is [block] starting from [begin].
  /// This class does not validate if the written Sub Piece is a duplicate; it simply overwrites the previous content.
  Future<bool> writeFile(int pieceIndex, int begin, List<int> block) async {
    var tempFiles = _piece2fileMap?[pieceIndex];
    // TODO: Does this work for last piece?
    // this is the start position relative to  start of the entire torrent block
    var startByte = pieceIndex * metainfo.pieceLength + begin;
    var blockSize = block.length;
    // this is the end position relative to  start of the entire torrent block
    var endByte = startByte + blockSize;
    if (tempFiles == null || tempFiles.isEmpty) return false;
    var futures = <Future<bool>>[];
    for (var i = 0; i < tempFiles.length; i++) {
      var tempFile = tempFiles[i];
      var re =
          blockToDownloadFilePosition(startByte, endByte, blockSize, tempFile);
      if (re == null) continue;
      futures.add(tempFile.requestWrite(
          re.position, block, re.blockStart, re.blockEnd));
    }
    var written = await Stream.fromFutures(futures).fold<bool>(true, (p, a) {
      return p && a;
    });

    if (written) {
      events.emit(SubPieceWriteCompleted(pieceIndex, begin, blockSize));
    } else {
      events.emit(SubPieceWriteFailed(pieceIndex, begin, blockSize));
    }

    return written;
  }

  Future close() async {
    events.dispose();
    await _stateFile.close();
    for (var i = 0; i < _files.length; i++) {
      var file = _files.elementAt(i);
      await file.close();
    }
    _clean();
  }

  void _clean() {
    _file2pieceMap.clear();
    _piece2fileMap = null;
  }

  Future delete() async {
    await _stateFile.delete();
    for (var i = 0; i < _files.length; i++) {
      var file = _files.elementAt(i);
      await file.delete();
    }
    _clean();
  }
}
