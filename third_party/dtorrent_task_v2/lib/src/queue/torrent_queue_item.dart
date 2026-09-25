import 'package:dtorrent_task_v2/src/torrent/torrent_model.dart';
import 'package:dtorrent_task_v2/src/piece/sequential_config.dart';
import 'package:dtorrent_task_v2/src/proxy/proxy_config.dart';

/// Priority levels for torrent queue items
enum QueuePriority {
  /// High priority - processed first
  high,

  /// Normal priority - default priority
  normal,

  /// Low priority - processed last
  low,
}

/// Represents a torrent item in the download queue
class TorrentQueueItem {
  /// Unique identifier for this queue item
  final String id;

  /// Torrent metadata
  final TorrentModel metaInfo;

  /// Path where the torrent will be saved
  final String savePath;

  /// Priority level (high, normal, low)
  final QueuePriority priority;

  /// Whether to stream the torrent
  final bool stream;

  /// Web seed URLs (BEP 0019)
  final List<Uri>? webSeeds;

  /// Acceptable source URLs (BEP 0019)
  final List<Uri>? acceptableSources;

  /// Sequential download configuration
  final SequentialConfig? sequentialConfig;

  /// Proxy configuration
  final ProxyConfig? proxyConfig;

  /// Timestamp when the item was added to the queue
  final DateTime addedAt;

  /// Optional user-defined metadata
  final Map<String, dynamic>? metadata;

  TorrentQueueItem({
    required this.metaInfo,
    required this.savePath,
    this.priority = QueuePriority.normal,
    this.stream = false,
    this.webSeeds,
    this.acceptableSources,
    this.sequentialConfig,
    this.proxyConfig,
    String? id,
    this.metadata,
  })  : id = id ?? _generateId(),
        addedAt = DateTime.now();

  /// Generate a unique ID for the queue item
  static String _generateId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${(1000 + (9999 - 1000) * (DateTime.now().microsecond / 1000000)).toInt()}';
  }

  /// Get priority as integer (higher number = higher priority)
  int get priorityValue {
    switch (priority) {
      case QueuePriority.high:
        return 3;
      case QueuePriority.normal:
        return 2;
      case QueuePriority.low:
        return 1;
    }
  }

  /// Create a copy of this item with modified fields
  TorrentQueueItem copyWith({
    TorrentModel? metaInfo,
    String? savePath,
    QueuePriority? priority,
    bool? stream,
    List<Uri>? webSeeds,
    List<Uri>? acceptableSources,
    SequentialConfig? sequentialConfig,
    ProxyConfig? proxyConfig,
    String? id,
    Map<String, dynamic>? metadata,
  }) {
    return TorrentQueueItem(
      metaInfo: metaInfo ?? this.metaInfo,
      savePath: savePath ?? this.savePath,
      priority: priority ?? this.priority,
      stream: stream ?? this.stream,
      webSeeds: webSeeds ?? this.webSeeds,
      acceptableSources: acceptableSources ?? this.acceptableSources,
      sequentialConfig: sequentialConfig ?? this.sequentialConfig,
      proxyConfig: proxyConfig ?? this.proxyConfig,
      id: id ?? this.id,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'TorrentQueueItem(id: $id, name: ${metaInfo.name}, priority: $priority, addedAt: $addedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TorrentQueueItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
