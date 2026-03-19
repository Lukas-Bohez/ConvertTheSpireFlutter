import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

import '../models/search_result.dart';
import 'log_service.dart';

/// Periodically checks watched playlists for new tracks.
///
/// On mobile platforms a WorkManager / background service would be ideal,
/// but for desktop / MVP this works via an in-process periodic timer.
class WatchedPlaylistService {
  final Future<List<SearchResult>> Function(String url) fetchPlaylistTracks;
  final Future<void> Function(SearchResult track) onNewTrack;
  final LogService? logs;

  WatchedPlaylistService({
    required this.fetchPlaylistTracks,
    required this.onNewTrack,
    this.logs,
  });

  bool _disposed = false;
  Timer? _pollTimer;

  /// Starts periodic playlist checks in-process (while app is alive).
  void startAutoCheck({Duration interval = const Duration(hours: 3)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) async {
      if (_disposed) return;
      await checkAllPlaylists();
    });
  }

  /// Stops periodic auto-checking.
  void stopAutoCheck() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Release any resources and stop background activity.
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ─── Persistence ─────────────────────────────────────────────────────────

  Future<List<String>> getWatchedUrls() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('watched_playlists') ?? [];
  }

  Future<void> addPlaylist(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('watched_playlists') ?? [];
    if (!list.contains(url)) {
      list.add(url);
      await prefs.setStringList('watched_playlists', list);
    }
    // Store initial snapshot
    await _snapshotPlaylist(url);
  }

  Future<void> removePlaylist(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('watched_playlists') ?? [];
    list.remove(url);
    await prefs.setStringList('watched_playlists', list);
    await prefs.remove('pl_hash_$url');
    await prefs.remove('pl_tracks_$url');
    await prefs.remove('pl_folder_$url');
  }

  Future<String?> getFolderForPlaylist(String url) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('pl_folder_$url');
  }

  Future<void> setFolderForPlaylist(String url, String folder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pl_folder_$url', folder);
  }

  Future<void> removeFolderForPlaylist(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pl_folder_$url');
  }

  // ─── Checking for new tracks ─────────────────────────────────────────────

  Future<int> checkAllPlaylists() async {
    if (_disposed) return 0;
    final urls = await getWatchedUrls();
    int totalNew = 0;
    for (final url in urls) {
      if (_disposed) break;
      totalNew += await checkPlaylist(url);
    }
    return totalNew;
  }

  Future<int> checkPlaylist(String url) async {
    if (_disposed) return 0;
    try {
      final currentTracks = await fetchPlaylistTracks(url);
      final currentHash = _hashTrackIds(currentTracks);

      final prefs = await SharedPreferences.getInstance();
      final storedHash = prefs.getString('pl_hash_$url');

      if (storedHash == null) {
        // First run – just store
        await _storeTracks(url, currentTracks, currentHash);
        return 0;
      }

      if (currentHash == storedHash) return 0;

      // Something changed
      final storedIds = await _getStoredIds(url);
      final newTracks =
          currentTracks.where((t) => !storedIds.contains(t.id)).toList();

      for (final track in newTracks) {
        await onNewTrack(track);
      }

      await _storeTracks(url, currentTracks, currentHash);
      logs?.add('Watched playlist: ${newTracks.length} new tracks in $url');
      return newTracks.length;
    } catch (e) {
      logs?.add('Watched playlist check failed for $url: $e');
      return 0;
    }
  }

  // ─── Internal helpers ────────────────────────────────────────────────────

  Future<void> _snapshotPlaylist(String url) async {
    if (_disposed) return;
    try {
      final tracks = await fetchPlaylistTracks(url);
      final hash = _hashTrackIds(tracks);
      await _storeTracks(url, tracks, hash);
    } catch (_) {}
  }

  Future<void> _storeTracks(
      String url, List<SearchResult> tracks, String hash) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pl_hash_$url', hash);
    final ids = tracks.map((t) => t.id).toList();
    await prefs.setStringList('pl_tracks_$url', ids);
  }

  Future<Set<String>> _getStoredIds(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('pl_tracks_$url') ?? [];
    return ids.toSet();
  }

  String _hashTrackIds(List<SearchResult> tracks) {
    final ids = tracks.map((t) => t.id).join(',');
    return md5.convert(utf8.encode(ids)).toString();
  }
}
