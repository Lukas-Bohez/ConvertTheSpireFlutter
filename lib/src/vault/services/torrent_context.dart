import 'package:convert_the_spire_reborn/src/vault/models/torrent.dart';
import 'package:convert_the_spire_reborn/src/vault/services/search_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_engine_service.dart';
import 'package:flutter/foundation.dart';

class TorrentContextService extends ChangeNotifier {
  bool _notifyPending = false;
  String currentQuery = '';
  String category = 'All';
  SearchResult? selectedResult;
  List<TorrentModel> activeDownloads = const <TorrentModel>[];
  List<TorrentModel> library = const <TorrentModel>[];
  final Map<String, TorrentEngineStatus> _runtimeStatusById =
      <String, TorrentEngineStatus>{};

  void updateQuery(String value) {
    currentQuery = value;
    _scheduleNotify();
  }

  void updateCategory(String value) {
    category = value;
    _scheduleNotify();
  }

  void updateSelected(SearchResult? result) {
    selectedResult = result;
    _scheduleNotify();
  }

  void updateTorrents(List<TorrentModel> all) {
    activeDownloads = all.where((t) {
      final status = (t.status ?? '').toLowerCase();
      return status.contains('download') ||
          status.contains('seed') ||
          status.contains('queued');
    }).toList();

    library = all.where((t) {
      final status = (t.status ?? '').toLowerCase();
      return status.contains('complete');
    }).toList();
    _scheduleNotify();
  }

  void updateRuntimeStatus(TorrentEngineStatus status) {
    if (status.torrentId.isEmpty) return;
    _runtimeStatusById[status.torrentId] = status;
    _scheduleNotify();
  }

  void _scheduleNotify() {
    if (_notifyPending) return;
    _notifyPending = true;
    Future.microtask(() {
      _notifyPending = false;
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  String getContext() {
    final selected = selectedResult;
    final selectedRuntime =
        selected == null ? null : _runtimeStatusById[selected.torrentId];
    final selectedTorrent = selected == null
        ? null
        : activeDownloads.cast<TorrentModel?>().firstWhere(
              (t) => t?.id == selected.torrentId,
              orElse: () => null,
            );
    final selectedSeeders = selectedRuntime?.seeders ??
        selectedTorrent?.seeders ??
        selected?.seeders;
    final selectedLeechers = selectedRuntime?.leechers ??
        selectedTorrent?.leechers ??
        selected?.leechers;
    final selectedStats = <String>[];
    if ((selectedSeeders ?? 0) > 0) {
      selectedStats.add('seeders: $selectedSeeders');
    }
    if ((selectedLeechers ?? 0) > 0) {
      selectedStats.add('leechers: $selectedLeechers');
    }
    final selectedStatsText = selectedStats.isEmpty
        ? 'no positive swarm stats'
        : selectedStats.join(' | ');
    final selectedText = selected == null
        ? 'No torrent selected.'
        : '${selected.name} | size: ${selected.size ?? 0} bytes | '
            '$selectedStatsText | '
            'source: ${selected.source.isEmpty ? selected.responderId : selected.source} | '
            'category: $category';

    final active = activeDownloads.isEmpty
        ? 'No active downloads.'
        : activeDownloads.map((t) {
            final runtime = _runtimeStatusById[t.id];
            final progress = runtime == null
                ? '${_pct(t)}%'
                : runtime.state.toLowerCase().contains('seed')
                    ? '${(runtime.seedingProgress * 100).toStringAsFixed(1)}% seeded-back'
                    : '${(runtime.progress * 100).toStringAsFixed(1)}%';
            final peers = runtime?.peers ?? 0;
            final seeders = [runtime?.seeders ?? 0, t.seeders]
                .reduce((a, b) => a > b ? a : b);
            final leechers = [runtime?.leechers ?? 0, t.leechers]
                .reduce((a, b) => a > b ? a : b);
            final uploaded = runtime?.uploaded ?? t.bytesUp;
            final state = runtime?.state ?? t.status ?? 'unknown';
            final stats = <String>[];
            if (peers > 0) stats.add('peers: $peers');
            if (seeders > 0) stats.add('seeders: $seeders');
            if (leechers > 0) stats.add('leechers: $leechers');
            if (uploaded > 0) stats.add('uploaded: $uploaded B');
            final statsText =
                stats.isEmpty ? 'no positive swarm stats' : stats.join(' | ');
            return '${t.name} [$state] $progress | $statsText';
          }).join(', ');

    final liveSeeders = _runtimeStatusById.values
        .map((s) => s.seeders)
        .fold<int>(0, (a, b) => a + b);
    final liveLeechers = _runtimeStatusById.values
        .map((s) => s.leechers)
        .fold<int>(0, (a, b) => a + b);
    final livePeers = _runtimeStatusById.values
        .map((s) => s.peers)
        .fold<int>(0, (a, b) => a + b);
    final liveUploadBytes = _runtimeStatusById.values
        .map((s) => s.uploaded)
        .fold<int>(0, (a, b) => a + b);

    final completed = library.isEmpty
        ? 'Library is empty.'
        : library.map((t) => t.name).join(', ');

    final queryText = currentQuery.isEmpty ? 'No active search.' : currentQuery;

    final liveStats = <String>[];
    if (livePeers > 0) liveStats.add('peers=$livePeers');
    if (liveSeeders > 0) liveStats.add('seeders=$liveSeeders');
    if (liveLeechers > 0) liveStats.add('leechers=$liveLeechers');
    if (liveUploadBytes > 0) liveStats.add('uploaded=$liveUploadBytes bytes');
    final liveText =
        liveStats.isEmpty ? 'no positive swarm stats' : liveStats.join(', ');

    return 'Current torrent search query: $queryText\n'
        'Selected torrent: $selectedText\n'
        'Live swarm snapshot: $liveText\n'
        'Active downloads: $active\n'
        'Library contents: $completed';
  }

  String _pct(TorrentModel torrent) {
    if (torrent.totalSize == null || torrent.totalSize == 0) return '0.0';
    final value = (torrent.bytesDown / torrent.totalSize!) * 100;
    return value.clamp(0, 100).toStringAsFixed(1);
  }
}
