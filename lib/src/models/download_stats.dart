/// Download statistics tracked for the dashboard.
class DownloadStats {
  int totalDownloads;
  int successfulDownloads;
  int failedDownloads;
  Map<String, int> downloadsByDate;
  Map<String, int> downloadsByArtist;
  Map<String, int> downloadsBySource;
  Map<String, int> downloadsByFormat;

  DownloadStats({
    this.totalDownloads = 0,
    this.successfulDownloads = 0,
    this.failedDownloads = 0,
    Map<String, int>? downloadsByDate,
    Map<String, int>? downloadsByArtist,
    Map<String, int>? downloadsBySource,
    Map<String, int>? downloadsByFormat,
  })  : downloadsByDate = downloadsByDate ?? {},
        downloadsByArtist = downloadsByArtist ?? {},
        downloadsBySource = downloadsBySource ?? {},
        downloadsByFormat = downloadsByFormat ?? {};

  double get successRate {
    if (totalDownloads == 0) return 0.0;
    return (successfulDownloads / totalDownloads) * 100;
  }

  void recordDownload({
    required bool success,
    required String artist,
    required String source,
    required String format,
  }) {
    totalDownloads++;
    if (success) {
      successfulDownloads++;
    } else {
      failedDownloads++;
    }

    final today = DateTime.now().toIso8601String().split('T')[0];
    downloadsByDate[today] = (downloadsByDate[today] ?? 0) + 1;
    downloadsByArtist[artist] = (downloadsByArtist[artist] ?? 0) + 1;
    downloadsBySource[source] = (downloadsBySource[source] ?? 0) + 1;
    downloadsByFormat[format] = (downloadsByFormat[format] ?? 0) + 1;
  }

  Map<String, dynamic> toJson() => {
        'total': totalDownloads,
        'successful': successfulDownloads,
        'failed': failedDownloads,
        'by_date': downloadsByDate,
        'by_artist': downloadsByArtist,
        'by_source': downloadsBySource,
        'by_format': downloadsByFormat,
      };

  factory DownloadStats.fromJson(Map<String, dynamic> json) {
    return DownloadStats(
      totalDownloads: (json['total'] as num?)?.toInt() ?? 0,
      successfulDownloads: (json['successful'] as num?)?.toInt() ?? 0,
      failedDownloads: (json['failed'] as num?)?.toInt() ?? 0,
      downloadsByDate: _mapFromJson(json['by_date']),
      downloadsByArtist: _mapFromJson(json['by_artist']),
      downloadsBySource: _mapFromJson(json['by_source']),
      downloadsByFormat: _mapFromJson(json['by_format']),
    );
  }

  static Map<String, int> _mapFromJson(dynamic data) {
    if (data is! Map) return {};
    return data.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }

  /// Top N entries from a count-map, sorted descending.
  static List<MapEntry<String, int>> topEntries(Map<String, int> map, [int n = 10]) {
    final entries = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).toList();
  }
}
