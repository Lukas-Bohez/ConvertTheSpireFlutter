import 'dart:convert';
import 'dart:typed_data';

class TorrentModel {
  final String id;
  final String name;
  final int? totalSize;
  final int? totalPieces;
  final int? pieceLength;
  final String? piecesHave;
  final String? status;
  final String type;
  final String? vaultKey;
  final String? filePath;
  final String? vaultLink;
  final String? magnetLink;
  final int bytesDown;
  final int seeders;
  final int leechers;
  final double reputation;
  final int bytesUp;
  final int? addedAt;
  final int? completedAt;
  final bool isSequential;
  final String? selectedFiles;
  final double? maxSeedRatio;
  final bool deleteAfterRatioReached;

  double get progress {
    if (totalPieces == null || totalPieces == 0) {
      return 0.0;
    }
    final have = piecesHave?.split(',').where((e) => e == '1').length ?? 0;
    return have / totalPieces!;
  }

  int get havePieces {
    return piecesHave?.split(',').where((e) => e == '1').length ?? 0;
  }

  TorrentModel({
    required this.id,
    required this.name,
    required this.type,
    this.totalSize,
    this.totalPieces,
    this.pieceLength,
    this.piecesHave,
    this.status,
    this.vaultKey,
    this.filePath,
    this.vaultLink,
    this.magnetLink,
    this.bytesDown = 0,
    this.bytesUp = 0,
    this.addedAt,
    this.completedAt,
    this.isSequential = false,
    this.selectedFiles,
    this.maxSeedRatio,
    this.deleteAfterRatioReached = false,
    this.seeders = 0,
    this.leechers = 0,
    this.reputation = 0.0,
  });

  TorrentModel copyWith({
    String? id,
    String? name,
    int? totalSize,
    int? totalPieces,
    int? pieceLength,
    String? piecesHave,
    String? status,
    String? type,
    String? vaultKey,
    String? filePath,
    String? vaultLink,
    String? magnetLink,
    int? bytesDown,
    int? bytesUp,
    int? addedAt,
    int? completedAt,
    bool? isSequential,
    String? selectedFiles,
    double? maxSeedRatio,
    bool? deleteAfterRatioReached,
    int? seeders,
    int? leechers,
    double? reputation,
  }) {
    return TorrentModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      totalSize: totalSize ?? this.totalSize,
      totalPieces: totalPieces ?? this.totalPieces,
      pieceLength: pieceLength ?? this.pieceLength,
      piecesHave: piecesHave ?? this.piecesHave,
      status: status ?? this.status,
      vaultKey: vaultKey ?? this.vaultKey,
      filePath: filePath ?? this.filePath,
      vaultLink: vaultLink ?? this.vaultLink,
      magnetLink: magnetLink ?? this.magnetLink,
      bytesDown: bytesDown ?? this.bytesDown,
      bytesUp: bytesUp ?? this.bytesUp,
      addedAt: addedAt ?? this.addedAt,
      completedAt: completedAt ?? this.completedAt,
      isSequential: isSequential ?? this.isSequential,
      selectedFiles: selectedFiles ?? this.selectedFiles,
      maxSeedRatio: maxSeedRatio ?? this.maxSeedRatio,
      deleteAfterRatioReached:
          deleteAfterRatioReached ?? this.deleteAfterRatioReached,
      seeders: seeders ?? this.seeders,
      leechers: leechers ?? this.leechers,
      reputation: reputation ?? this.reputation,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'total_size': totalSize,
      'total_pieces': totalPieces,
      'piece_length': pieceLength,
      'pieces_have': piecesHave,
      'status': status,
      'type': type,
      'vault_key': vaultKey,
      'file_path': filePath,
      'vault_link': vaultLink,
      'magnet_link': magnetLink,
      'bytes_down': bytesDown,
      'bytes_up': bytesUp,
      'added_at': addedAt,
      'completed_at': completedAt,
      'is_sequential': isSequential ? 1 : 0,
      'selected_files': selectedFiles,
      'max_seed_ratio': maxSeedRatio,
      'delete_after_ratio_reached': deleteAfterRatioReached ? 1 : 0,
      'seeders': seeders,
      'leechers': leechers,
      'reputation': reputation,
    };
  }

  factory TorrentModel.fromMap(Map<String, dynamic> map) {
    String? stringify(dynamic value) {
      if (value is String) return value;
      if (value == null) return null;
      if (value is Uint8List) return utf8.decode(value);
      return value.toString();
    }

    return TorrentModel(
      id: stringify(map['id']) ?? '',
      name: stringify(map['name']) ?? '',
      type: stringify(map['type']) ?? '',
      totalSize: map['total_size'] as int?,
      totalPieces: map['total_pieces'] as int?,
      pieceLength: map['piece_length'] as int?,
      piecesHave: stringify(map['pieces_have']),
      status: stringify(map['status']),
      vaultKey: stringify(map['vault_key']),
      filePath: stringify(map['file_path']),
      vaultLink: stringify(map['vault_link']),
      magnetLink: stringify(map['magnet_link']),
      bytesDown: map['bytes_down'] as int? ?? 0,
      bytesUp: map['bytes_up'] as int? ?? 0,
      addedAt: map['added_at'] as int?,
      completedAt: map['completed_at'] as int?,
      isSequential: (map['is_sequential'] as int? ?? 0) == 1,
      selectedFiles: stringify(map['selected_files']),
      maxSeedRatio: (map['max_seed_ratio'] as num?)?.toDouble(),
      deleteAfterRatioReached:
          (map['delete_after_ratio_reached'] as int? ?? 0) == 1,
      seeders: map['seeders'] as int? ?? 0,
      leechers: map['leechers'] as int? ?? 0,
      reputation: (map['reputation'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
