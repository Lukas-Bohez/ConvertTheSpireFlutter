/// Represents a file in a torrent (v1 format)
/// Compatible with TorrentFile from dtorrent_parser
class TorrentFileModel {
  /// File path (relative to torrent root)
  final String path;

  /// File name (last component of path)
  String get name => path.split('/').last;

  /// File length in bytes
  final int length;

  /// File offset in the torrent (for v1 format)
  final int offset;

  /// End position of the file
  int get end => offset + length;

  TorrentFileModel({
    required this.path,
    required this.length,
    required this.offset,
  });

  @override
  String toString() =>
      'TorrentFileModel(path: $path, length: $length, offset: $offset)';
}
