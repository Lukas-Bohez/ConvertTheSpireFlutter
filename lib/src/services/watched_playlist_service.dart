import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/search_result.dart';
import 'log_service.dart';

/// One independently-addressable "watch" of a playlist.
///
/// The same [url] can be watched more than once, pointing at different
/// [folder] / [format] combinations — [id] (not the URL) is the unique key.
/// A null [folder] / [format] means "use the app's default download
/// folder/format".
class WatchedPlaylistEntry {
  final String id;
  final String url;
  final String? folder;
  final String? format;

  const WatchedPlaylistEntry({
    required this.id,
    required this.url,
    this.folder,
    this.format,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'url': url,
        'folder': folder,
        'format': format,
      };

  static WatchedPlaylistEntry fromMap(Map<String, dynamic> map) {
    final folder = map['folder'];
    final format = map['format'];
    return WatchedPlaylistEntry(
      id: (map['id'] as String?) ?? '',
      url: (map['url'] as String?) ?? '',
      folder: folder is String && folder.trim().isNotEmpty ? folder : null,
      format: format is String && format.trim().isNotEmpty ? format : null,
    );
  }
}

/// Periodically checks watched playlists for new tracks.
///
/// On mobile platforms a WorkManager / background service would be ideal,
/// but for desktop / MVP this works via an in-process periodic timer.
class WatchedPlaylistService {
  final Future<List<SearchResult>> Function(String url) fetchPlaylistTracks;
  final Future<void> Function(String playlistUrl, SearchResult track,
      {String? folder, String? format}) onNewPlaylistTrack;
  final LogService? logs;

  static const _entriesKey = 'watched_playlist_entries';
  static const _legacyUrlListKey = 'watched_playlists';

  WatchedPlaylistService({
    required this.fetchPlaylistTracks,
    required this.onNewPlaylistTrack,
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

  // --- Persistence -------------------------------------------------------

  /// Loads the current watched-playlist entries, migrating the legacy
  /// `watched_playlists` URL list + `pl_folder_*` keys the first time the
  /// new `watched_playlist_entries` key is missing.
  ///
  /// The legacy keys are intentionally left in place after migration so the
  /// conversion can always be re-inspected or re-run.
  Future<List<WatchedPlaylistEntry>> getEntries() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadEntries(prefs);
  }

  /// The distinct URLs currently being watched (convenience for callers that
  /// only need a URL list; identically-watched URLs collapse to one entry).
  Future<List<String>> getWatchedUrls() async {
    final entries = await getEntries();
    final seen = <String>{};
    final urls = <String>[];
    for (final e in entries) {
      if (seen.add(e.url)) urls.add(e.url);
    }
    return urls;
  }
/// Adds a new watched-playlist entry.
  ///
  /// There is deliberately no dedupe on [url]: the same playlist can be
  /// watched more than once with different [folder] / [format] destinations.
  /// Uniqueness lives at the entry level (each entry gets a fresh [id]).
  /// The first entry watching a URL snapshots the shared
  /// `pl_hash_$url` / `pl_tracks_$url` state once; later entries reuse it.
  Future<WatchedPlaylistEntry> addEntry({
    required String url,
    String? folder,
    String? format,
  }) async {
    final normalized = url.trim();
    final prefs = await SharedPreferences.getInstance();
    final entries = await _loadEntries(prefs);
    final alreadyWatched = entries.any((e) => e.url == normalized);
    final entry = WatchedPlaylistEntry(
      id: const Uuid().v4(),
      url: normalized,
      folder: _nonEmpty(folder),
      format: _safeFormat(format),
    );
    entries.add(entry);
    await _saveEntries(prefs, entries);
    if (!alreadyWatched) {
      // First watcher seeds the shared per-URL snapshot.
      await _snapshotPlaylist(normalized);
    }
    return entry;
  }

  /// Updates the folder / format destination of an existing entry.
  Future<void> updateEntry(
    String id, {
    String? folder,
    String? format,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await _loadEntries(prefs);
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].id == id) {
        entries[i] = WatchedPlaylistEntry(
          id: entries[i].id,
          url: entries[i].url,
          folder: _nonEmpty(folder),
          format: _safeFormat(format),
        );
        break;
      }
    }
    await _saveEntries(prefs, entries);
  }

  /// Removes a single entry.
  ///
  /// The shared `pl_hash_$url` / `pl_tracks_$url` state for an entry's URL is
  /// only cleaned up when the entry was the last watcher of that URL — other
  /// entries watching the same playlist keep the shared snapshot intact.
  Future<void> removeEntry(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await _loadEntries(prefs);
    final removed = <WatchedPlaylistEntry>[];
    entries.removeWhere((e) {
      if (e.id == id) {
        removed.add(e);
        return true;
      }
      return false;
    });
    if (removed.isEmpty) return;
    await _saveEntries(prefs, entries);
    final url = removed.first.url;
    if (!entries.any((e) => e.url == url)) {
      await prefs.remove('pl_hash_$url');
      await prefs.remove('pl_tracks_$url');
    }
  }
// -- Checking for new tracks -------------------------------------------

  Future<int> checkAllPlaylists() async {
    if (_disposed) return 0;
    final entries = await getEntries();
    int totalNew = 0;
    // Group entries by URL so each unique playlist is fetched / diffed
    // exactly once per cycle: multiple entries watching the same URL share
    // one check instead of re-hitting YouTube per entry.
    final byUrl = <String, List<WatchedPlaylistEntry>>{};
    for (final e in entries) {
      (byUrl[e.url] ??= <WatchedPlaylistEntry>[]).add(e);
    }
    for (final group in byUrl.values) {
      if (_disposed) break;
      totalNew += await _checkUrl(group);
    }
    return totalNew;
  }

  /// Fetches the playlist at [watchers]' shared URL once, diffs it against
  /// the stored snapshot, and hands each new track to EVERY entry in
  /// [watchers] (each downloading to its own folder/format).
  Future<int> _checkUrl(List<WatchedPlaylistEntry> watchers) async {
    final url = watchers.first.url;
    try {
      final currentTracks = await fetchPlaylistTracks(url);
      final currentHash = _hashTrackIds(currentTracks);

      final prefs = await SharedPreferences.getInstance();
      final storedHash = prefs.getString('pl_hash_$url');

      if (storedHash == null) {
        // First time we've seen this URL — seed the snapshot, nothing new.
        await _storeTracks(url, currentTracks, currentHash);
        return 0;
      }

      if (currentHash == storedHash) return 0;

      // Something changed — diff against the stored ids.
      final storedIds = await _getStoredIds(url);
      final newTracks =
          currentTracks.where((t) => !storedIds.contains(t.id)).toList();

      for (final track in newTracks) {
        for (final watcher in watchers) {
          await onNewPlaylistTrack(url, track,
              folder: watcher.folder, format: watcher.format);
        }
      }

      await _storeTracks(url, currentTracks, currentHash);
      logs?.add('Watched playlist: ${newTracks.length} new tracks in $url');
      return newTracks.length;
    } catch (e) {
      logs?.add('Watched playlist check failed for $url: $e');
      return 0;
    }
  }
// -- Internal helpers ---------------------------------------------------

  Future<List<WatchedPlaylistEntry>> _loadEntries(
      SharedPreferences prefs) async {
    final raw = prefs.getString(_entriesKey);
    if (raw != null && raw.trim().isNotEmpty) {
      return _decodeEntries(raw);
    }
    return _migrateLegacy(prefs);
  }

  /// Converts the pre-13.1 flat "URL list + per-format folder keys" storage
  /// into individual entries: one entry per non-empty folder key found
  /// (default, mp3, m4a, mp4); a URL with no folder becomes a single
  /// default-destination entry. The legacy keys are left in place.
  Future<List<WatchedPlaylistEntry>> _migrateLegacy(
      SharedPreferences prefs) async {
    final legacyUrls = prefs.getStringList(_legacyUrlListKey) ?? [];
    if (legacyUrls.isEmpty) return [];

    final entries = <WatchedPlaylistEntry>[];
    for (final url in legacyUrls) {
      final defaultFolder = _nonEmpty(prefs.getString('pl_folder_$url'));
      final mp3Folder = _nonEmpty(prefs.getString('pl_folder_mp3_$url'));
      final m4aFolder = _nonEmpty(prefs.getString('pl_folder_m4a_$url'));
      final mp4Folder = _nonEmpty(prefs.getString('pl_folder_mp4_$url'));

      if (defaultFolder == null &&
          mp3Folder == null &&
          m4aFolder == null &&
          mp4Folder == null) {
        entries.add(WatchedPlaylistEntry(
          id: const Uuid().v4(),
          url: url,
        ));
      } else {
        if (defaultFolder != null) {
          entries.add(WatchedPlaylistEntry(
            id: const Uuid().v4(),
            url: url,
            folder: defaultFolder,
          ));
        }
        if (mp3Folder != null) {
          entries.add(WatchedPlaylistEntry(
            id: const Uuid().v4(),
            url: url,
            folder: mp3Folder,
            format: 'mp3',
          ));
        }
        if (m4aFolder != null) {
          entries.add(WatchedPlaylistEntry(
            id: const Uuid().v4(),
            url: url,
            folder: m4aFolder,
            format: 'm4a',
          ));
        }
        if (mp4Folder != null) {
          entries.add(WatchedPlaylistEntry(
            id: const Uuid().v4(),
            url: url,
            folder: mp4Folder,
            format: 'mp4',
          ));
        }
      }
    }

    await _saveEntries(prefs, entries);
    return entries;
  }

  Future<void> _saveEntries(
      SharedPreferences prefs, List<WatchedPlaylistEntry> entries) async {
    await prefs.setString(
        _entriesKey, jsonEncode(entries.map((e) => e.toMap()).toList()));
  }

  List<WatchedPlaylistEntry> _decodeEntries(String raw) {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final entries = <WatchedPlaylistEntry>[];
    for (final item in decoded) {
      if (item is Map) {
        try {
          entries
              .add(WatchedPlaylistEntry.fromMap(item.cast<String, dynamic>()));
        } catch (_) {
          // Skip malformed entries, keep the rest.
        }
      }
    }
    return entries;
  }
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

  String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Only keeps formats the downloader can actually handle ('mp3', 'm4a',
  /// 'mp4'); anything else is treated as "use the app default format".
  String? _safeFormat(String? format) {
    final f = _nonEmpty(format);
    if (f == null) return null;
    return const {'mp3', 'm4a', 'mp4'}.contains(f.toLowerCase())
        ? f.toLowerCase()
        : null;
  }
}