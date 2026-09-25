import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dtorrent_task_v2/src/torrent/torrent_model.dart';
import 'package:logging/logging.dart';
import '../peer/bitfield.dart';
import 'file_priority.dart';

var _log = Logger('StateFileV2');

/// Current state file format version
const int STATE_FILE_VERSION = 2;

/// Magic bytes to identify state file format
const List<int> STATE_FILE_MAGIC = [
  0x44,
  0x54,
  0x53,
  0x46
]; // "DTSF" (DTorrent State File)

/// Header structure:
/// - Magic bytes (4 bytes)
/// - Version (4 bytes, uint32)
/// - Info hash (20 bytes for SHA1, 32 bytes for SHA256)
/// - Piece count (4 bytes, uint32)
/// - Piece length (8 bytes, uint64)
/// - Total length (8 bytes, uint64)
/// - Uploaded bytes (8 bytes, uint64)
/// - Timestamp (8 bytes, uint64, milliseconds since epoch)
/// - Storage flags (1 byte): bit 0 = compressed, bit 1 = sparse, bits 2-7 = reserved
/// - Compression level (1 byte): 0-9 for zlib, 255 = no compression
/// - Reserved (2 bytes)
/// - Header checksum (4 bytes, CRC32 of header)
/// Total header: 72 bytes (4+4+20+4+8+8+8+8+1+1+2+4)

/// Storage format flags
const int FLAG_COMPRESSED = 0x01;
const int FLAG_SPARSE = 0x02;

/// Threshold for using sparse storage (if completed pieces < this percentage, use sparse)
const double SPARSE_THRESHOLD = 0.1; // 10%

/// Threshold for using compression (if bitfield size > this, compress)
const int COMPRESSION_THRESHOLD = 1024; // 1KB

/// Enhanced state file with versioning, validation, and recovery support
class StateFileV2 {
  late Bitfield _bitfield;
  bool _closed = false;
  int _uploaded = 0;
  final TorrentModel metainfo;
  File? _bitfieldFile;

  /// Whether the file is behind what is here.
  bool _dirty = false;
  Timer? _saveTimer;
  Future<void>? _saving;

  /// State file metadata
  int _version = STATE_FILE_VERSION;
  DateTime? _lastModified;
  bool _isValid = false;
  bool _compressed = false;
  bool _sparse = false;
  int _compressionLevel = 6; // Default zlib compression level

  /// File priorities (only non-normal priorities are stored)
  Map<int, FilePriority> _filePriorities = {};

  /// Get file priorities
  Map<int, FilePriority> get filePriorities =>
      Map.unmodifiable(_filePriorities);

  /// Set file priorities
  void setFilePriorities(Map<int, FilePriority> priorities) {
    _filePriorities = Map.from(priorities);
    // Remove normal priorities (they're default)
    _filePriorities
        .removeWhere((index, priority) => priority == FilePriority.normal);
  }

  bool get isClosed => _closed;
  bool get isValid => _isValid;
  int get version => _version;
  DateTime? get lastModified => _lastModified;

  StateFileV2(this.metainfo);

  /// Get state file with automatic migration from old format
  static Future<StateFileV2> getStateFile(
      String directoryPath, TorrentModel metainfo) async {
    var stateFile = StateFileV2(metainfo);
    await stateFile.init(directoryPath, metainfo);
    return stateFile;
  }

  Bitfield get bitfield => _bitfield;

  int get downloaded {
    var downloaded = bitfield.completedPieces.length * metainfo.pieceLength;
    if (bitfield.completedPieces.contains(bitfield.piecesNum - 1)) {
      downloaded -= metainfo.pieceLength - metainfo.lastPieceLength;
    }
    return downloaded;
  }

  int get uploaded => _uploaded;

  /// Initialize state file with validation and migration support
  Future<File> init(String directoryPath, TorrentModel metainfo) async {
    var lastChar = directoryPath.substring(directoryPath.length - 1);
    if (lastChar != Platform.pathSeparator) {
      directoryPath = directoryPath + Platform.pathSeparator;
    }

    _bitfieldFile = File('$directoryPath${metainfo.infoHash}.bt.state');
    var exists = await _bitfieldFile?.exists();

    if (exists != null && !exists) {
      // Create new state file with v2 format
      _bitfieldFile = await _bitfieldFile?.create(recursive: true);
      if (metainfo.pieces == null) {
        throw StateError(
            'Cannot create state file: torrent has no pieces (v2-only torrent?)');
      }
      _bitfield = Bitfield.createEmptyBitfield(metainfo.pieces!.length);
      _uploaded = 0;
      _version = STATE_FILE_VERSION;
      _lastModified = DateTime.now();
      _isValid = true;
      await _writeFile();
    } else {
      // Try to load existing state file
      await _loadStateFile();
    }

    return _bitfieldFile!;
  }

  /// Writes the whole state file at once.
  Future<void> _writeFile() async {
    final file = _bitfieldFile;
    if (file == null) return;
    await file.writeAsBytes(_serialize());
  }

  /// The state file's bytes: header, bitfield section, file priorities,
  /// uploaded bytes and the bitfield's checksum.
  Uint8List _serialize() {
    // Decides the storage flags the header records.
    final bitfield = _bitfieldSection();
    final uploaded = ByteData(8)..setUint64(0, _uploaded, Endian.little);
    final checksum = ByteData(4)
      ..setUint32(0, bitfield.checksum, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(_headerBytes())
          ..add(bitfield.bytes)
          ..add(_prioritiesBytes())
          ..add(uploaded.buffer.asUint8List())
          ..add(checksum.buffer.asUint8List()))
        .takeBytes();
  }

  /// The v2 format header.
  Uint8List _headerBytes() {
    if (metainfo.pieces == null) {
      throw StateError(
          'Cannot write header: torrent has no pieces (v2-only torrent?)');
    }
    final header = ByteData(72);
    for (var i = 0; i < STATE_FILE_MAGIC.length; i++) {
      header.setUint8(i, STATE_FILE_MAGIC[i]);
    }
    header.setUint32(4, _version, Endian.little);
    // Info hash: 20 bytes, the start of a longer (v2) one.
    final infoHash = metainfo.infoHashBuffer;
    for (var i = 0; i < infoHash.length && i < 20; i++) {
      header.setUint8(8 + i, infoHash[i]);
    }
    header.setUint32(28, metainfo.pieces!.length, Endian.little);
    header.setUint64(32, metainfo.pieceLength, Endian.little);
    header.setUint64(40, metainfo.length ?? metainfo.totalSize, Endian.little);
    header.setUint64(48, _uploaded, Endian.little);
    final timestamp = _lastModified ?? DateTime.now();
    header.setUint64(56, timestamp.millisecondsSinceEpoch, Endian.little);
    var flags = 0;
    if (_compressed) flags |= FLAG_COMPRESSED;
    if (_sparse) flags |= FLAG_SPARSE;
    header.setUint8(64, flags);
    header.setUint8(65, _compressed ? _compressionLevel : 255);
    // 66-67 reserved; the checksum covers the first 68 bytes.
    header.setUint32(
        68, _calculateCRC32(header.buffer.asUint8List(0, 68)), Endian.little);
    return header.buffer.asUint8List();
  }

  /// The bitfield as stored, and the checksum the footer keeps of it:
  /// sparse (the completed pieces' indices) while under [SPARSE_THRESHOLD]
  /// of the pieces are complete, else the bitfield, compressed when that
  /// makes it smaller. Sets [_sparse] and [_compressed] to match.
  ({Uint8List bytes, int checksum}) _bitfieldSection() {
    final completed = _bitfield.completedPieces;
    final totalPieces = _bitfield.piecesNum;
    final completionRatio =
        totalPieces > 0 ? completed.length / totalPieces : 0.0;
    if (completionRatio < SPARSE_THRESHOLD && completed.isNotEmpty) {
      _sparse = true;
      _compressed = false;
      final bytes = ByteData(4 + completed.length * 4)
        ..setUint32(0, completed.length, Endian.little);
      for (var i = 0; i < completed.length; i++) {
        bytes.setUint32(4 + i * 4, completed[i], Endian.little);
      }
      final list = bytes.buffer.asUint8List();
      return (bytes: list, checksum: _calculateCRC32(list.sublist(4)));
    }

    _sparse = false;
    _compressed = false;
    final raw = _bitfield.buffer;
    var data = raw;
    if (raw.length >= COMPRESSION_THRESHOLD) {
      try {
        final compressed = gzip.encoder.convert(raw);
        if (compressed.length < raw.length) {
          _compressed = true;
          data = Uint8List.fromList(compressed);
        }
      } catch (e) {
        _log.warning('Compression failed, using uncompressed', e);
      }
    }
    final checksum = _calculateCRC32(raw);
    if (!_compressed) return (bytes: data, checksum: checksum);
    final size = ByteData(4)..setUint32(0, data.length, Endian.little);
    return (
      bytes: (BytesBuilder(copy: false)
            ..add(size.buffer.asUint8List())
            ..add(data))
          .takeBytes(),
      checksum: checksum
    );
  }

  /// File priorities section.
  /// Format: count (4 bytes) + for each file: index (4 bytes) + priority (1 byte)
  Uint8List _prioritiesBytes() {
    // Only write non-normal priorities
    final nonNormalPriorities = _filePriorities.entries
        .where((e) => e.value != FilePriority.normal)
        .toList();
    final data = ByteData(4 + nonNormalPriorities.length * 5)
      ..setUint32(0, nonNormalPriorities.length, Endian.little);
    var offset = 4;
    for (var entry in nonNormalPriorities) {
      data.setUint32(offset, entry.key, Endian.little);
      data.setUint8(offset + 4, entry.value.value);
      offset += 5;
    }
    return data.buffer.asUint8List();
  }

  /// Read file priorities section
  Future<void> _readFilePriorities(Uint8List bytes, int offset) async {
    if (bytes.length < offset + 4) {
      _log.fine('No file priorities section in state file (old format)');
      _filePriorities = {};
      return;
    }

    // Read count
    final countView = ByteData.view(bytes.buffer, offset, 4);
    final count = countView.getUint32(0, Endian.little);
    offset += 4;

    if (count == 0) {
      _filePriorities = {};
      return;
    }

    // Check if we have enough data
    if (bytes.length < offset + (count * 5)) {
      _log.warning('File priorities section incomplete, skipping');
      _filePriorities = {};
      return;
    }

    // Read priorities
    _filePriorities = {};
    var currentOffset = offset;
    for (var i = 0; i < count; i++) {
      final fileView = ByteData.view(bytes.buffer, currentOffset, 5);
      final fileIndex = fileView.getUint32(0, Endian.little);
      final priorityValue = fileView.getUint8(4);

      // Convert value to FilePriority
      FilePriority priority;
      switch (priorityValue) {
        case 0:
          priority = FilePriority.skip;
          break;
        case 1:
          priority = FilePriority.low;
          break;
        case 2:
          priority = FilePriority.normal;
          break;
        case 3:
          priority = FilePriority.high;
          break;
        default:
          _log.warning(
              'Invalid priority value $priorityValue for file $fileIndex, using normal');
          priority = FilePriority.normal;
      }

      _filePriorities[fileIndex] = priority;
      currentOffset += 5;
    }

    _log.fine('Read ${_filePriorities.length} file priorities from state file');
  }

  /// Load state file with format detection and migration
  Future<void> _loadStateFile() async {
    if (_bitfieldFile == null) return;

    try {
      final bytes = await _bitfieldFile!.readAsBytes();

      // Check if it's v2 format (has magic bytes)
      if (bytes.length >= 4 &&
          bytes[0] == STATE_FILE_MAGIC[0] &&
          bytes[1] == STATE_FILE_MAGIC[1] &&
          bytes[2] == STATE_FILE_MAGIC[2] &&
          bytes[3] == STATE_FILE_MAGIC[3]) {
        // Load v2 format
        await _loadV2Format(bytes);
      } else {
        // Migrate from v1 format
        await _migrateFromV1(bytes);
      }
    } catch (e, stackTrace) {
      _log.warning(
          'Failed to load state file, creating new one', e, stackTrace);
      _isValid = false;
      // Create new state file
      if (metainfo.pieces == null) {
        throw StateError(
            'Cannot create bitfield: torrent has no pieces (v2-only torrent?)');
      }
      _bitfield = Bitfield.createEmptyBitfield(metainfo.pieces!.length);
      _uploaded = 0;
      _version = STATE_FILE_VERSION;
      _lastModified = DateTime.now();
      await _writeFile();
      _isValid = true;
    }
  }

  /// Load v2 format state file
  Future<void> _loadV2Format(Uint8List bytes) async {
    if (bytes.length < 72) {
      throw Exception('State file too short');
    }

    final header = ByteData.view(bytes.buffer, 0, 72);
    var offset = 4; // Skip magic

    // Read version
    _version = header.getUint32(offset, Endian.little);
    offset += 4;

    // Validate info hash
    offset += 20; // Skip info hash

    // Read piece count
    final pieceCount = header.getUint32(offset, Endian.little);
    offset += 4;

    // Read piece length
    final pieceLength = header.getUint64(offset, Endian.little);
    offset += 8;

    // Validate piece count and length match torrent
    if (metainfo.pieces == null) {
      throw StateError(
          'Cannot validate: torrent has no pieces (v2-only torrent?)');
    }
    if (pieceCount != metainfo.pieces!.length ||
        pieceLength != metainfo.pieceLength) {
      throw Exception('State file does not match torrent');
    }

    // Read uploaded
    offset += 8; // Skip total length
    _uploaded = header.getUint64(offset, Endian.little);
    offset += 8;

    // Read timestamp
    final timestamp = header.getUint64(offset, Endian.little);
    _lastModified = DateTime.fromMillisecondsSinceEpoch(timestamp);
    offset += 8;

    // Read storage flags
    final flags = header.getUint8(offset++);
    _compressed = (flags & FLAG_COMPRESSED) != 0;
    _sparse = (flags & FLAG_SPARSE) != 0;

    // Read compression level
    _compressionLevel = header.getUint8(offset++);
    if (_compressionLevel == 255) _compressionLevel = 6; // Default

    // Skip reserved
    offset += 2;

    // Validate header checksum
    final headerBytes = bytes.sublist(0, 68);
    final expectedChecksum = header.getUint32(68, Endian.little);
    final actualChecksum = _calculateCRC32(headerBytes);
    if (expectedChecksum != actualChecksum) {
      throw Exception('State file header checksum mismatch');
    }

    // Read bitfield
    final bitfieldStart = 72;
    var bitfieldDataOffset = bitfieldStart;

    if (_sparse) {
      // Read sparse bitfield
      _bitfield =
          await _readSparseBitfield(bytes, bitfieldDataOffset, pieceCount);
      // Calculate offset after sparse data
      final countData = ByteData.view(bytes.buffer, bitfieldDataOffset, 4);
      final completedCount = countData.getUint32(0, Endian.little);
      bitfieldDataOffset += 4 + (completedCount * 4);
    } else {
      // Read full bitfield (compressed or not)
      final bitfieldLength = (pieceCount / 8).ceil();
      var dataLength = bitfieldLength;

      if (_compressed) {
        // Read compressed size
        final sizeData = ByteData.view(bytes.buffer, bitfieldDataOffset, 4);
        dataLength = sizeData.getUint32(0, Endian.little);
        bitfieldDataOffset += 4;
      }

      if (bytes.length < bitfieldDataOffset + dataLength + 8 + 4) {
        throw Exception('State file incomplete');
      }

      var bitfieldBytes =
          bytes.sublist(bitfieldDataOffset, bitfieldDataOffset + dataLength);

      if (_compressed) {
        // Decompress
        try {
          bitfieldBytes =
              Uint8List.fromList(gzip.decoder.convert(bitfieldBytes));
          _log.fine(
              'Bitfield decompressed: $dataLength -> ${bitfieldBytes.length} bytes');
        } catch (e) {
          throw Exception('Failed to decompress bitfield: $e');
        }
      }

      _bitfield =
          Bitfield.copyFrom(pieceCount, bitfieldBytes, 0, bitfieldBytes.length);
      bitfieldDataOffset += dataLength;
    }

    // Read file priorities (after bitfield, before footer)
    var prioritiesOffset = bitfieldDataOffset;
    await _readFilePriorities(bytes, prioritiesOffset);

    // Calculate priorities section size
    // Note: _readFilePriorities reads the count first, so we need to calculate size
    // based on what was actually read
    final prioritiesCount = _filePriorities.length;
    final prioritiesSize =
        4 + (prioritiesCount * 5); // count + (index + priority) for each

    // Read uploaded from footer (for compatibility)
    final uploadedOffset = prioritiesOffset + prioritiesSize;
    if (bytes.length < uploadedOffset + 8 + 4) {
      // If file is too short, priorities might not be present (old format)
      if (bytes.length >= bitfieldDataOffset + 8 + 4) {
        // Try reading without priorities (old format)
        _filePriorities = {};
        final uploadedOffsetOld = bitfieldDataOffset;
        final uploadedView = ByteData.view(bytes.buffer, uploadedOffsetOld, 8);
        final uploadedFromFooter = uploadedView.getUint64(0, Endian.little);
        if (_uploaded != uploadedFromFooter) {
          _log.warning(
              'Uploaded mismatch between header and footer, using header value');
        }
        final checksumOffset = uploadedOffsetOld + 8;
        // Continue with checksum validation...
        final expectedBitfieldChecksum =
            ByteData.view(bytes.buffer, checksumOffset, 4)
                .getUint32(0, Endian.little);
        int actualBitfieldChecksum;
        if (_sparse) {
          final completedPieces = _bitfield.completedPieces;
          final indicesBytes = Uint8List(completedPieces.length * 4);
          final view = ByteData.view(indicesBytes.buffer);
          for (var i = 0; i < completedPieces.length; i++) {
            view.setUint32(i * 4, completedPieces[i], Endian.little);
          }
          actualBitfieldChecksum = _calculateCRC32(indicesBytes);
        } else {
          actualBitfieldChecksum = _calculateCRC32(_bitfield.buffer);
        }
        if (expectedBitfieldChecksum != actualBitfieldChecksum) {
          _log.warning(
              'Bitfield checksum mismatch, state file may be corrupted');
          _isValid = false;
        } else {
          _isValid = true;
        }
        return;
      }
      throw Exception('State file incomplete (missing footer)');
    }
    final uploadedView = ByteData.view(bytes.buffer, uploadedOffset, 8);
    final uploadedFromFooter = uploadedView.getUint64(0, Endian.little);
    if (_uploaded != uploadedFromFooter) {
      _log.warning(
          'Uploaded mismatch between header and footer, using header value');
    }

    // Validate bitfield checksum
    final checksumOffset = uploadedOffset + 8;
    final expectedBitfieldChecksum =
        ByteData.view(bytes.buffer, checksumOffset, 4)
            .getUint32(0, Endian.little);

    int actualBitfieldChecksum;
    if (_sparse) {
      final completedPieces = _bitfield.completedPieces;
      final indicesBytes = Uint8List(completedPieces.length * 4);
      final view = ByteData.view(indicesBytes.buffer);
      for (var i = 0; i < completedPieces.length; i++) {
        view.setUint32(i * 4, completedPieces[i], Endian.little);
      }
      actualBitfieldChecksum = _calculateCRC32(indicesBytes);
    } else {
      actualBitfieldChecksum = _calculateCRC32(_bitfield.buffer);
    }

    if (expectedBitfieldChecksum != actualBitfieldChecksum) {
      _log.warning('Bitfield checksum mismatch, state file may be corrupted');
      _isValid = false;
    } else {
      _isValid = true;
    }
  }

  /// Read sparse bitfield (only completed piece indices)
  Future<Bitfield> _readSparseBitfield(
      Uint8List bytes, int offset, int pieceCount) async {
    final bitfield = Bitfield.createEmptyBitfield(pieceCount);

    // Read count
    final countData = ByteData.view(bytes.buffer, offset, 4);
    final completedCount = countData.getUint32(0, Endian.little);
    offset += 4;

    // Read piece indices and set bits
    for (var i = 0; i < completedCount; i++) {
      final indexData = ByteData.view(bytes.buffer, offset, 4);
      final pieceIndex = indexData.getUint32(0, Endian.little);
      if (pieceIndex < pieceCount) {
        bitfield.setBit(pieceIndex, true);
      }
      offset += 4;
    }

    return bitfield;
  }

  /// Migrate from v1 format to v2 format
  Future<void> _migrateFromV1(Uint8List bytes) async {
    _log.info('Migrating state file from v1 to v2 format');

    if (metainfo.pieces == null) {
      throw StateError(
          'Cannot migrate: torrent has no pieces (v2-only torrent?)');
    }
    final piecesNum = metainfo.pieces!.length;
    final bitfieldBufferLength = (piecesNum / 8).ceil();

    if (bytes.length < bitfieldBufferLength + 8) {
      throw Exception('Invalid v1 state file format');
    }

    // Read bitfield from v1 format
    final bitfieldBytes = bytes.sublist(0, bitfieldBufferLength);
    _bitfield =
        Bitfield.copyFrom(piecesNum, bitfieldBytes, 0, bitfieldBufferLength);

    // Read uploaded from v1 format
    final uploadedView = ByteData.view(bytes.buffer, bitfieldBufferLength, 8);
    _uploaded = uploadedView.getUint64(0, Endian.little);

    _version = STATE_FILE_VERSION;
    _lastModified = DateTime.now();
    _isValid = true;

    // Write new v2 format
    await _writeFile();

    _log.info('State file migration completed');
  }

  /// Calculate CRC32 checksum
  int _calculateCRC32(List<int> data) {
    // Simple CRC32 implementation
    int crc = 0xFFFFFFFF;
    for (var byte in data) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc >> 1) ^ (0xEDB88320 & (-(crc & 1)));
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  /// How long a change waits before it is written, so the pieces completed
  /// meanwhile go in the same write.
  static const saveDelay = Duration(seconds: 2);

  /// Update piece bitfield
  ///
  /// The change takes effect at once and is written to the file within
  /// [saveDelay], or on [close]. The file used to be rewritten in many small
  /// writes, and flushed to the disk, after every piece: with small pieces
  /// that was most of what a download did, and it kept a slow disk busy.
  Future<bool> update(int index, {bool have = true, int uploaded = 0}) async {
    if (_closed) return false;
    if (index != -1) {
      if (_bitfield.getBit(index) == have && _uploaded == uploaded) {
        return false;
      }
      _bitfield.setBit(index, have);
    } else if (_uploaded == uploaded) {
      return false;
    }
    _uploaded = uploaded;
    _lastModified = DateTime.now();
    _dirty = true;
    _saveTimer ??= Timer(saveDelay, () {
      _saveTimer = null;
      unawaited(_save());
    });
    return true;
  }

  /// Writes the changes not in the file yet, one write at a time.
  Future<void> _save() async {
    while (_saving != null) {
      await _saving;
    }
    if (!_dirty || _bitfieldFile == null) return;
    _dirty = false;
    final saving = _writeFile().catchError((Object e) {
      _dirty = true;
      _log.warning('Could not write the state file', e);
    });
    _saving = saving;
    await saving;
    _saving = null;
  }

  Future<bool> updateBitfield(int index, [bool have = true]) async {
    if (_bitfield.getBit(index) == have) return false;
    return update(index, have: have, uploaded: _uploaded);
  }

  Future<bool> updateUploaded(int uploaded) async {
    if (_uploaded == uploaded) return false;
    return update(-1, uploaded: uploaded);
  }

  /// Writes what changed since the last write.
  Future<void> close() async {
    if (isClosed) return;
    _closed = true;
    _saveTimer?.cancel();
    _saveTimer = null;
    await _save();
  }

  Future<FileSystemEntity?> delete() async {
    _dirty = false;
    await close();
    var r = _bitfieldFile?.delete();
    _bitfieldFile = null;
    return r;
  }

  /// Validate state file integrity
  Future<bool> validate() async {
    if (_bitfieldFile == null) return false;
    try {
      final bytes = await _bitfieldFile!.readAsBytes();
      if (bytes.length < 72) return false;

      // Check magic bytes
      if (bytes[0] != STATE_FILE_MAGIC[0] ||
          bytes[1] != STATE_FILE_MAGIC[1] ||
          bytes[2] != STATE_FILE_MAGIC[2] ||
          bytes[3] != STATE_FILE_MAGIC[3]) {
        return false;
      }

      // Validate header checksum
      final headerBytes = bytes.sublist(0, 68);
      final expectedChecksum =
          ByteData.view(bytes.buffer, 68, 4).getUint32(0, Endian.little);
      final actualChecksum = _calculateCRC32(headerBytes);
      if (expectedChecksum != actualChecksum) return false;

      // Read bitfield section to determine its size
      final header = ByteData.view(bytes.buffer, 0, 72);
      var offset = 4; // Skip magic
      offset += 4; // Skip version
      offset += 20; // Skip info hash
      final pieceCount = header.getUint32(offset, Endian.little);
      offset += 4;
      offset += 8; // Skip piece length
      offset += 8; // Skip total length
      offset += 8; // Skip uploaded
      offset += 8; // Skip timestamp
      final flags = header.getUint8(offset++);
      final compressed = (flags & FLAG_COMPRESSED) != 0;
      final sparse = (flags & FLAG_SPARSE) != 0;
      offset += 1; // Skip compression level
      offset += 2; // Skip reserved

      // Calculate bitfield size
      var bitfieldSize = 0;
      var bitfieldStart = 72;
      if (sparse) {
        if (bytes.length < bitfieldStart + 4) return false;
        final countData = ByteData.view(bytes.buffer, bitfieldStart, 4);
        final completedCount = countData.getUint32(0, Endian.little);
        bitfieldSize = 4 + (completedCount * 4);
      } else {
        if (compressed) {
          if (bytes.length < bitfieldStart + 4) return false;
          final sizeData = ByteData.view(bytes.buffer, bitfieldStart, 4);
          bitfieldSize = 4 + sizeData.getUint32(0, Endian.little);
        } else {
          bitfieldSize = (pieceCount / 8).ceil();
        }
      }

      // Read priorities section size
      var prioritiesOffset = bitfieldStart + bitfieldSize;
      var prioritiesSize = 0;
      if (bytes.length >= prioritiesOffset + 4) {
        final countView = ByteData.view(bytes.buffer, prioritiesOffset, 4);
        final prioritiesCount = countView.getUint32(0, Endian.little);
        prioritiesSize = 4 + (prioritiesCount * 5);
      }

      // Validate bitfield checksum (after priorities section)
      final uploadedOffset = prioritiesOffset + prioritiesSize;
      if (bytes.length < uploadedOffset + 8 + 4) return false;

      final checksumOffset = uploadedOffset + 8;
      final expectedBitfieldChecksum =
          ByteData.view(bytes.buffer, checksumOffset, 4)
              .getUint32(0, Endian.little);

      int actualBitfieldChecksum;
      if (sparse) {
        if (bytes.length < bitfieldStart + bitfieldSize) return false;
        final completedPieces = <int>[];
        if (bitfieldSize > 4) {
          final indicesData =
              bytes.sublist(bitfieldStart + 4, bitfieldStart + bitfieldSize);
          for (var i = 0; i < indicesData.length; i += 4) {
            if (i + 4 <= indicesData.length) {
              final view = ByteData.view(indicesData.buffer, i, 4);
              completedPieces.add(view.getUint32(0, Endian.little));
            }
          }
        }
        final indicesBytes = Uint8List(completedPieces.length * 4);
        final view = ByteData.view(indicesBytes.buffer);
        for (var i = 0; i < completedPieces.length; i++) {
          view.setUint32(i * 4, completedPieces[i], Endian.little);
        }
        actualBitfieldChecksum = _calculateCRC32(indicesBytes);
      } else {
        Uint8List bitfieldBytes;
        if (compressed) {
          if (bytes.length < bitfieldStart + bitfieldSize) return false;
          final compressedData =
              bytes.sublist(bitfieldStart + 4, bitfieldStart + bitfieldSize);
          try {
            bitfieldBytes =
                Uint8List.fromList(gzip.decoder.convert(compressedData));
          } catch (e) {
            return false;
          }
        } else {
          if (bytes.length < bitfieldStart + bitfieldSize) return false;
          bitfieldBytes =
              bytes.sublist(bitfieldStart, bitfieldStart + bitfieldSize);
        }
        actualBitfieldChecksum = _calculateCRC32(bitfieldBytes);
      }

      if (expectedBitfieldChecksum != actualBitfieldChecksum) return false;

      return true;
    } catch (e) {
      _log.warning('State file validation failed', e);
      return false;
    }
  }
}
