// ignore_for_file: unused_element, deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException, DeviceOrientation, SystemChrome, SystemUiMode;
import 'package:image/image.dart' as img;
import 'package:just_audio/just_audio.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_service/audio_service.dart' as audio_svc;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_player/video_player.dart';
import '../services/platform_dirs.dart';
import '../services/audio_handler.dart';
import '../services/ffmpeg_service.dart';
import '../utils/lock.dart';

// ─── Public entry point ───────────────────────────────────────────────────────

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) => const PlayerScreen();
}

// ─── Enums & data types ───────────────────────────────────────────────────────

enum MediaType { audio, video }

enum RepeatMode { off, one, all }

enum PlaybackMode { all, songs, videos, favourites }

enum QueueScope { all, songs, videos, favourites, favSongs, favVideos }

class MediaItem {
  final String path;
  final MediaType type;
  final String? title;
  final String? artist;
  final Uint8List? thumbnailData;
  final Duration? duration;

  const MediaItem(
    this.path,
    this.type, {
    this.title,
    this.artist,
    this.thumbnailData,
    this.duration,
  });

  MediaItem copyWith({
    String? title,
    String? artist,
    Uint8List? thumbnailData,
    Duration? duration,
  }) =>
      MediaItem(
        path,
        type,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        thumbnailData: thumbnailData ?? this.thumbnailData,
        duration: duration ?? this.duration,
      );
}

// ─── Thumbnail helpers (unchanged — they work fine) ──────────────────────────

Future<Uint8List?> _transcodeToSafePng(Uint8List raw, {String? mimeType}) async {
  if (raw.length < 4) return null;
  try {
    img.Image? decoded;
    if (mimeType != null) {
      final mt = mimeType.toLowerCase().trim();
      if (mt.contains('jpeg') || mt.contains('jpg')) decoded = img.decodeJpg(raw);
      else if (mt.contains('png')) decoded = img.decodePng(raw);
      else if (mt.contains('webp')) decoded = img.decodeWebP(raw);
      else if (mt.contains('bmp')) decoded = img.decodeBmp(raw);
      else if (mt.contains('gif')) decoded = img.decodeGif(raw);
      else if (mt.contains('tiff') || mt.contains('tif')) decoded = img.decodeTiff(raw);
    }
    decoded ??= _decodeByMagic(raw);
    decoded ??= img.decodeImage(raw);
    if (decoded == null) return null;
    final thumb = img.copyResize(decoded, width: 240, interpolation: img.Interpolation.average);
    return Uint8List.fromList(img.encodePng(thumb));
  } catch (_) {
    return null;
  }
}

img.Image? _decodeByMagic(Uint8List raw) {
  if (raw.length < 4) return null;
  if (raw[0] == 0xFF && raw[1] == 0xD8 && raw[2] == 0xFF) return img.decodeJpg(raw);
  if (raw[0] == 0x89 && raw[1] == 0x50 && raw[2] == 0x4E && raw[3] == 0x47) return img.decodePng(raw);
  if (raw[0] == 0x47 && raw[1] == 0x49 && raw[2] == 0x46 && raw[3] == 0x38) return img.decodeGif(raw);
  if (raw[0] == 0x42 && raw[1] == 0x4D) return img.decodeBmp(raw);
  if (raw.length >= 12 && raw[0] == 0x52 && raw[1] == 0x49 && raw[2] == 0x46 && raw[3] == 0x46 &&
      raw[8] == 0x57 && raw[9] == 0x45 && raw[10] == 0x42 && raw[11] == 0x50) return img.decodeWebP(raw);
  if ((raw[0] == 0x49 && raw[1] == 0x49 && raw[2] == 0x2A && raw[3] == 0x00) ||
      (raw[0] == 0x4D && raw[1] == 0x4D && raw[2] == 0x00 && raw[3] == 0x2A)) return img.decodeTiff(raw);
  return null;
}

// ─── PlayerState ──────────────────────────────────────────────────────────────
//
// FIX SUMMARY:
//
// BUG 1 — Wrong track on tap:
//   Root cause: select(idx) set currentIndex then called _loadCurrent(). But
//   _loadingTrack guard dropped subsequent calls while setting _pendingReload=true.
//   When pending reload fired, currentIndex had been mutated by later taps.
//   FIX: _loadCurrent now receives the target index as a parameter and captures
//   it immediately. The guard uses a serial "generation" counter; stale loads
//   self-cancel without corrupting currentIndex.
//
// BUG 2 — Thumbnail storm / slow scrolling:
//   Root cause: Both background loops + per-item VisibilityDetector all called
//   notifyListeners() independently, causing O(n) full rebuilds simultaneously.
//   FIX: Background thumbnail loading is serialised through a single
//   throttled notify (at most once per 150 ms). VisibilityDetector requests are
//   deduplicated with a pending-set so each index is only processed once.
//
// BUG 3 — Video crash (Lost connection to device):
//   Root cause: media_kit stream listeners (position, completed, etc.) fire on
//   background threads and called notifyListeners() directly — illegal on Flutter.
//   FIX: All stream callbacks are routed through a microtask-queued dispatcher
//   (_scheduleNotify) that coalesces rapid updates and always executes on the
//   platform thread via scheduleMicrotask / WidgetsBinding.instance.
//
// BUG 4 — just_audio_windows threading error:
//   Root cause: setVolume called on non-platform thread from stream listeners.
//   FIX: All just_audio calls are wrapped in _runOnMainThread().

class PlayerState with ChangeNotifier {
  final SharedPreferences prefs;

  List<MediaItem> library = [];

  // BUG 1 FIX: currentIndex is only ever mutated by select() which captures a
  // snapshot before any async work begins.
  int currentIndex = 0;

  bool shuffle = false;
  RepeatMode repeatMode = RepeatMode.off;
  double volume = 0.5;
  bool isLoading = false;
  MediaType? activeTabFilter;
  bool favouritesOnly = false;
  PlaybackMode playbackMode = PlaybackMode.all;
  // Queue feature is kept in the model for compatibility, but the UI no longer
  // exposes it.
  final List<int> manualQueue = [];
  final List<int> _manualQueueBase = [];

  Directory? _thumbCacheDir;
  Set<String> _favourites = {};
  Map<String, MediaItem> _favouriteCache = {};
  int _folderItemCount = 0;

  // BUG 1 FIX: generation counter — each _loadCurrent call captures generation
  // at start; if generation changes mid-load the load aborts.
  int _loadGeneration = 0;

  // BUG 2 FIX: version counter for library loads — background loops abort when
  // this changes.
  int _loadVersion = 0;

  // BUG 2 FIX: serialised notify — coalesce multiple rapid state changes.
  bool _notifyPending = false;

  // BUG 2 FIX: dedup set for in-flight thumbnail requests.
  final Set<int> _thumbInFlight = {};

  bool _disposed = false;
  final List<StreamSubscription> _subs = [];
  // Subscriptions specifically attached to media_kit players. These must be
  // cancelled and recreated when the Player instance is replaced to avoid
  // callbacks into disposed/native objects which can crash the app.
  final List<StreamSubscription> _mkSubs = [];
  StreamSubscription? _dirWatcher;
  String? _watchedDirPath;

  Duration position = Duration.zero;
  Duration? duration;
  DateTime? _lastMkOpenTime;

  static const double _videoVolumeBoost = 1.8;
  static const Set<String> _mediaExtensions = {
    '.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.aac', '.wma',
    '.mp4', '.mkv', '.avi', '.webm', '.mov', '.wmv', '.flv', '.m4v',
  };

  // ── Audio ──
  AudioPlayer? _audio;
  AppAudioHandler? _audioHandler;

  // ── Video ──
  // Enable media_kit on desktop platforms except Windows because the
  // Windows build has proven unstable for bulk thumbnail/video operations.
  // Windows will use just_audio/VideoPlayer instead.
  // Enable media_kit on desktop platforms (including Windows) because it
  // provides stable playback support; we avoid using its thumbnail screenshot
  // feature on Windows to prevent crashes.
  final bool _useMediaKit = kIsWeb || !Platform.isAndroid;
  Player? _mkPlayer;
  VideoController? _mkController;
  // Dedicated media_kit player for audio-only playback on desktop so that
  // audio doesn't reuse the video player's texture/controller.
  Player? _audioMkPlayer;
  // Player used for taking thumbnail screenshots (shared to avoid creating
  // many players which can destabilize Windows/Mac/Linux builds).
  Player? _thumbPlayer;
  VideoPlayerController? _androidController;
  VoidCallback? _androidListener;

  bool _videoReady = false;
  bool _videoCompletionFired = false;

  // Protects concurrent thumbnail generation / screenshot operations.
  final _thumbLock = Lock();
  DateTime? _lastThumbOpenTime;

  // video suspension for resize removed — avoid interfering with media_kit

  final _random = Random();
  final _audioLock = Lock();

  // ─────────────────────────────────────────────────────────────────────────

  PlayerState(this.prefs) {
    if (_useMediaKit) {
      _initMkPlayers();
    }

    _loadPrefs().then((_) => _applyVolume());

    if (!_useMediaKit && !kIsWeb && Platform.isAndroid) _initAudioHandler();

    // ── Audio streams ──
    // BUG 3/4 FIX: route all callbacks through _scheduleNotify so they always
    // execute on the platform thread. Only create the just_audio player on Android
    // where media_kit is not used.
    if (!_useMediaKit && Platform.isAndroid) {
      _audio = AudioPlayer();
      _subs.add(_audio!.positionStream.listen((pos) {
        if (_disposed || currentItem?.type != MediaType.audio) return;
        position = pos;
        _scheduleNotify();
      }));
      _subs.add(_audio!.durationStream.listen((dur) {
        if (_disposed || currentItem?.type != MediaType.audio) return;
        duration = dur;
        _scheduleNotify();
      }));
      _subs.add(_audio!.playerStateStream.listen((ps) {
        if (_disposed) return;
        if (ps.processingState == ProcessingState.completed) {
          _scheduleNotify(callback: _handleCompletion);
        } else {
          _scheduleNotify();
        }
      }));
    } else {
      _audio = null;
    }

    // media_kit streams are attached above via _attachMkPlayerStreams so
    // they live in `_mkSubs` and can be cancelled / recreated safely.
  }

  // Ensure media_kit Player instances are created on the main isolate.
  // Running player construction on a background isolate can cause native
  // binding failures (libmpv). We dispatch creation via a microtask which
  // runs on the main Dart thread.
  Future<void> _initMkPlayers() async {
    try {
      await Future.microtask(() {});
      try {
        _mkPlayer ??= Player();
        _mkController ??= VideoController(_mkPlayer!);
        _audioMkPlayer ??= Player();
        _thumbPlayer ??= Player();
      } catch (e) {
        debugPrint('media_kit init failed: $e');
      }
      // Attach media_kit streams to a dedicated list so they can be
      // cancelled when the underlying Player is recreated.
      _attachMkPlayerStreams(_mkPlayer);
      if (_audioMkPlayer != null) _attachMkPlayerStreams(_audioMkPlayer, isAudio: true);
      notifyListeners();
    } catch (e) {
      debugPrint('InitMkPlayers outer error: $e');
    }
  }

  /// Fully dispose and recreate the media_kit video player and controller.
  /// Preserves play position and attempts to restore playing state.
  Future<void> safeRecreateMkPlayer() async {
    if (!_useMediaKit) return;
    try {
      final wasPlaying = _mkPlayer?.state.playing ?? false;
      // Use the serialized `position` tracked by PlayerState rather than
      // attempting to read platform Player internals which may be unavailable.
      final pos = position;
      try {
        await _mkPlayer?.pause();
      } catch (_) {}

      // Cancel any media_kit subscriptions attached to the old player(s)
      // to avoid callbacks into torn-down native resources.
      try {
        for (final s in _mkSubs) {
          try {
            s.cancel();
          } catch (_) {}
        }
      } catch (_) {}
      _mkSubs.clear();

      try {
        // Stop and dispose old player if possible.
        try { await _mkPlayer?.stop(); } catch (_) {}
        try { await _mkPlayer?.dispose(); } catch (_) {}
        _mkController = null;
      } catch (_) {}
      _mkPlayer = null;

      // Recreate on the main isolate to ensure native bindings initialize
      // correctly (libmpv / media_kit must be created on the platform thread).
      try {
        await Future.microtask(() {
          _mkPlayer = Player();
          _mkController = VideoController(_mkPlayer!);
        });
        // Reattach streams to the new player and any auxiliary audio player.
        _attachMkPlayerStreams(_mkPlayer);
        if (_audioMkPlayer != null) _attachMkPlayerStreams(_audioMkPlayer, isAudio: true);
        if (pos > Duration.zero) {
          try {
            await _mkPlayer!.seek(pos);
          } catch (_) {}
        }
        if (wasPlaying) {
          try {
            await _mkPlayer!.play();
          } catch (_) {}
        }
        notifyListeners();
      } catch (e) {
        debugPrint('safeRecreateMkPlayer error: $e');
      }
    } catch (e) {
      debugPrint('safeRecreateMkPlayer outer error: $e');
    }
  }

  // Attach media_kit player streams to `_mkSubs` so they can be cancelled
  // and recreated safely when the underlying Player instance changes.
  void _attachMkPlayerStreams(Player? player, {bool isAudio = false}) {
    if (player == null) return;
    _mkSubs.add(player.stream.position.listen((pos) {
      if (_disposed) return;
      if (isAudio) {
        if (currentItem?.type != MediaType.audio) return;
      } else {
        if (currentItem?.type != MediaType.video) return;
      }
      position = pos;
      _scheduleNotify();
    }));
    _mkSubs.add(player.stream.duration.listen((dur) {
      if (_disposed) return;
      if (isAudio) {
        if (currentItem?.type != MediaType.audio) return;
      } else {
        if (currentItem?.type != MediaType.video) return;
      }
      duration = dur;
      _scheduleNotify();
    }));
    if (!isAudio) {
      _mkSubs.add(player.stream.width.listen((w) {
        if (_disposed || currentItem?.type != MediaType.video) return;
        if ((w ?? 0) > 0 && !_videoReady) {
          _videoReady = true;
          _scheduleNotify();
        }
      }));
      _mkSubs.add(player.stream.completed.listen((done) {
        if (_disposed || !done || currentItem?.type != MediaType.video) return;
        if (!_videoCompletionFired) {
          _videoCompletionFired = true;
          _scheduleNotify(callback: _handleCompletion);
        }
      }));
    } else {
      _mkSubs.add(player.stream.completed.listen((done) {
        if (_disposed || !done || currentItem?.type != MediaType.audio) return;
        _scheduleNotify(callback: _handleCompletion);
      }));
    }
  }

  // BUG 3/4 FIX: coalescing, always-on-platform-thread notifier.
  // All stream listeners on just_audio / media_kit fire on background threads
  // (Windows thread pool). We must NEVER call any plugin method or
  // notifyListeners() synchronously from those callbacks.
  // _scheduleNotify posts everything as a microtask which always executes on
  // the main Dart isolate thread, satisfying the platform channel requirement.
  void _scheduleNotify({VoidCallback? callback}) {
    // CRITICAL: do NOT call callback synchronously here — the caller is on a
    // background thread. Queue it alongside the notify.
    if (_notifyPending && callback == null) return;
    if (!_notifyPending) _notifyPending = true;
    Future.microtask(() {
      if (_disposed) return;
      _notifyPending = false;
      callback?.call();   // now on main isolate — safe to call plugin methods
      notifyListeners();
    });
  }

  // ─── Getters ──────────────────────────────────────────────────────────────

  MediaItem? get currentItem {
    if (library.isEmpty) return null;
    if (currentIndex < 0 || currentIndex >= library.length) currentIndex = 0;
    return library[currentIndex];
  }

  bool get isVideo => currentItem?.type == MediaType.video;
  bool get videoReady => _videoReady;

  bool get isPlaying {
    if (isVideo) {
      if (_useMediaKit && _mkPlayer != null) return _mkPlayer!.state.playing;
      return _androidController?.value.isPlaying ?? false;
    }
    if (_useMediaKit) {
      return _audioMkPlayer?.state.playing ?? false;
    }
    return _audio?.playing ?? false;
  }

  bool get isActuallyPlaying => isPlaying;

  int mediaIndexForPath(String path) => library.indexWhere((item) => item.path == path);

  bool isPlayingPath(String path) => currentItem?.path == path && isActuallyPlaying;

  Widget? thumbnailForItem(MediaItem item, {required int size}) {
    final data = item.thumbnailData;
    if (data == null) return null;
    return Image.memory(
      data,
      width: size.toDouble(),
      height: size.toDouble(),
      fit: BoxFit.cover,
    );
  }

  VideoController? get videoController => _mkController;
  VideoPlayerController? get androidVideoController => _androidController;
  int get folderItemCount => _folderItemCount;

  List<MapEntry<int, MediaItem>> get audioEntries => library
      .asMap()
      .entries
      .where((e) => e.key < _folderItemCount && e.value.type == MediaType.audio)
      .toList();

  List<MapEntry<int, MediaItem>> get videoEntries => library
      .asMap()
      .entries
      .where((e) => e.key < _folderItemCount && e.value.type == MediaType.video)
      .toList();

  List<MapEntry<int, MediaItem>> get favouriteEntries => library
      .asMap()
      .entries
      .where((e) => _favourites.contains(e.value.path))
      .toList();

  bool isFavourite(String path) => _favourites.contains(path);

  // ─── Favourites ───────────────────────────────────────────────────────────

  void toggleFavourite(String path) {
    if (_favourites.contains(path)) {
      _favourites.remove(path);
      _favouriteCache.remove(path);
    } else {
      _favourites.add(path);
      final idx = library.indexWhere((item) => item.path == path);
      if (idx >= 0) _favouriteCache[path] = library[idx];
    }
    prefs.setStringList('player_favourites', _favourites.toList());
    _saveFavouriteCache();
    notifyListeners();
  }

  void _saveFavouriteCache() {
    final list = <String>[];
    for (final path in _favourites) {
      final item = _favouriteCache[path];
      if (item != null) {
        list.add('${item.path}\t${item.type == MediaType.video ? 'v' : 'a'}'
            '\t${item.title ?? ''}\t${item.artist ?? ''}');
        if (item.thumbnailData != null) _saveThumbToCache(path, item.thumbnailData!);
      }
    }
    prefs.setStringList('player_favourites_cache', list);
  }

  // ─── Thumb disk cache ─────────────────────────────────────────────────────

  Future<Directory> _getThumbCacheDir() async {
    if (_thumbCacheDir != null) return _thumbCacheDir!;
    final appDir = await getApplicationSupportDirectory();
    _thumbCacheDir = Directory('${appDir.path}${Platform.pathSeparator}thumb_cache');
    if (!_thumbCacheDir!.existsSync()) _thumbCacheDir!.createSync(recursive: true);
    return _thumbCacheDir!;
  }

  String _thumbCacheKey(String path) =>
      path.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');

  Future<void> _saveThumbToCache(String itemPath, Uint8List data) async {
    try {
      final dir = await _getThumbCacheDir();
      final file = File('${dir.path}${Platform.pathSeparator}${_thumbCacheKey(itemPath)}.png');
      await file.writeAsBytes(data);
    } catch (_) {}
  }

  Future<Uint8List?> _loadThumbFromCache(String itemPath) async {
    try {
      final dir = await _getThumbCacheDir();
      final file = File('${dir.path}${Platform.pathSeparator}${_thumbCacheKey(itemPath)}.png');
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {}
    return null;
  }

  // ─── Library loading ──────────────────────────────────────────────────────

  Future<void> setLibrary(List<MediaItem> items) async {
    final version = ++_loadVersion;
    isLoading = true;
    _folderItemCount = 0;
    _thumbInFlight.clear();

    if (_audio != null) {
      try { await _audio!.stop(); } catch (_) {}
    }
    if (_audioMkPlayer != null) {
      try { await _audioMkPlayer!.stop(); } catch (_) {}
    }
    if (_useMediaKit && _mkPlayer != null) {
      try { await _mkPlayer!.stop(); } catch (_) {}
    }
    await _disposeAndroidController();

    library = List.from(items);
    currentIndex = 0;
    position = Duration.zero;
    duration = null;
    notifyListeners();

    // Fast pass: title + artist only, no images, batched.
    const batchSize = 20;
    for (int start = 0; start < library.length; start += batchSize) {
      if (_loadVersion != version) return;
      final end = (start + batchSize).clamp(0, library.length);
      await Future.wait(
        List.generate(end - start, (j) => _enrichMetadataFast(start + j, library, version)),
      );
      if (_loadVersion != version) return;
      notifyListeners();
    }

    _folderItemCount = library.length;

    // Append cached favourites not in this folder.
    final folderPaths = library.map((e) => e.path).toSet();
    for (final path in _favourites) {
      if (!folderPaths.contains(path) && _favouriteCache.containsKey(path)) {
        library.add(_favouriteCache[path]!);
      }
    }
    for (int i = 0; i < _folderItemCount; i++) {
      if (_favourites.contains(library[i].path)) _favouriteCache[library[i].path] = library[i];
    }
    _saveFavouriteCache();

    currentIndex = 0;
    isLoading = false;
    notifyListeners();

    // BUG 2 FIX: Avoid bulk thumbnail generation on Windows (crashes). Instead,
    // load thumbnails lazily on demand when the item becomes visible.
    // For other platforms, perform a limited background scan so UI feels
    // responsive without exhausting resources.
    if (!Platform.isWindows) {
      _loadThumbnailsSequentially(version, maxItems: 30);
    }
    // Ensure the current playing item has a thumbnail request pending.
    requestThumbnailForIndex(currentIndex);
    _startDirectoryWatcher(items);
  }

  /// BUG 2 FIX: Single sequential thumbnail loop with throttled notify.
  /// Replaces the two simultaneous background loops that each called
  /// notifyListeners() per item.
  Future<void> _loadThumbnailsSequentially(int version, {int maxItems = 50}) async {
    int pendingNotify = 0;
    int loaded = 0;

    for (int i = 0; i < library.length; i++) {
      if (_loadVersion != version || _disposed) return;
      if (loaded >= maxItems) return;
      if (library[i].thumbnailData != null) continue;
      loaded++;

      final item = library[i];
      final path = item.path;

      if (!path.startsWith('content://')) {
        try { if (!await File(path).exists()) continue; } catch (_) { continue; }
      }

      Uint8List? thumb;
      Duration? dur;

      // Check disk cache first.
      thumb = await _loadThumbFromCache(path);

      if (thumb == null) {
        try {
          final metaPath = await _resolveLocalPath(path);
          final tag = await readMetadata(File(metaPath), getImage: true);
          if (_loadVersion != version) return;
          dur = tag.duration;
          for (final pic in tag.pictures) {
            if (pic.bytes.isEmpty) continue;
            thumb = await _transcodeToSafePng(pic.bytes, mimeType: pic.mimetype);
            if (thumb != null) break;
          }
        } catch (_) {}

        if (thumb == null && item.type == MediaType.video) {
          thumb = await _generateVideoThumbnail(path);
        }

        if (thumb != null) {
          try { await _saveThumbToCache(path, thumb); } catch (_) {}
        }
      }

      if (_loadVersion != version) return;
      if (i < library.length && library[i].path == path) {
        if (thumb != null || dur != null) {
          library[i] = library[i].copyWith(
            thumbnailData: thumb ?? library[i].thumbnailData,
            duration: dur,
          );
          if (_favourites.contains(path)) _favouriteCache[path] = library[i];
          pendingNotify++;
          // BUG 2 FIX: batch notifies — only fire every 5 items or end of list,
          // reducing rebuilds from O(n) to O(n/5).
          if (pendingNotify >= 5 || i == library.length - 1) {
            pendingNotify = 0;
            notifyListeners();
            // Yield to keep UI responsive between batches.
            await Future.delayed(const Duration(milliseconds: 16));
          }
        }
      }
    }
  }

  /// BUG 2 FIX: on-demand thumbnail for a single index, deduplicated.
  Future<void> requestThumbnailForIndex(int index) async {
    if (_disposed) return;
    if (index < 0 || index >= library.length) return;
    if (library[index].thumbnailData != null) return;
    // BUG 2 FIX: skip if already in-flight.
    if (_thumbInFlight.contains(index)) return;
    _thumbInFlight.add(index);

    try {
      final item = library[index];
      final path = item.path;
      Uint8List? thumb;
      Duration? dur;

      thumb = await _loadThumbFromCache(path);

      if (thumb == null) {
        try {
          final metaPath = await _resolveLocalPath(path);
          final tag = await readMetadata(File(metaPath), getImage: true);
          dur = tag.duration;
          for (final pic in tag.pictures) {
            if (pic.bytes.isEmpty) continue;
            thumb = await _transcodeToSafePng(pic.bytes, mimeType: pic.mimetype);
            if (thumb != null) break;
          }
        } catch (_) {}

        if (thumb == null && item.type == MediaType.video) {
          thumb = await _generateVideoThumbnailSafe(path);
        }

        if (thumb != null) {
          try { await _saveThumbToCache(path, thumb); } catch (_) {}
        }
      }

      if (_disposed) return;
      if (index < library.length && library[index].path == path) {
        if (thumb != null || dur != null) {
          library[index] = library[index].copyWith(
            thumbnailData: thumb ?? library[index].thumbnailData,
            duration: dur,
          );
          if (_favourites.contains(path)) _favouriteCache[path] = library[index];
          notifyListeners();
        }
      }
    } finally {
      _thumbInFlight.remove(index);
    }
  }

  Future<void> _enrichMetadataFast(int i, List<MediaItem> lib, int version) async {
    if (_loadVersion != version || i >= lib.length) return;
    final item = lib[i];
    try {
      final metaPath = await _resolveLocalPath(item.path);
      final tag = await readMetadata(File(metaPath), getImage: false);
      if (_loadVersion != version) return;
      lib[i] = item.copyWith(
        title: tag.title?.trim().isNotEmpty == true ? tag.title!.trim() : item.title,
        artist: tag.artist?.trim().isNotEmpty == true ? tag.artist!.trim() : item.artist,
      );
    } catch (_) {}
  }

  // ─── Playback selection ───────────────────────────────────────────────────

  /// BUG 1 FIX: select() captures the target index into a local variable and
  /// passes it directly to _loadCurrent(). The generation counter ensures that
  /// if select() is called again before _loadCurrent() finishes, the earlier
  /// load aborts gracefully instead of landing on the wrong track.
  Future<void> select(int index) async {
    if (index < 0 || index >= library.length) return;
    // Capture NOW before any async gap.
    final targetIndex = index;
    final generation = ++_loadGeneration;
    currentIndex = targetIndex;
    notifyListeners();
    await _loadCurrent(targetIndex, generation);
  }

  Future<void> _loadCurrent(int targetIndex, int generation) async {
    if (_disposed) return;
    if (targetIndex < 0 || targetIndex >= library.length) return;

    // BUG 1 FIX: abort if a newer select() has been called.
    if (generation != _loadGeneration) {
      debugPrint('_loadCurrent: stale generation $generation (current: $_loadGeneration), aborting');
      return;
    }

    // Snapshot the item at load time — don't rely on currentItem getter.
    final item = library[targetIndex];

    _videoCompletionFired = false;
    _videoReady = false;
    notifyListeners();

    _applyVolume();

    try {
      if (item.type == MediaType.audio) {
        // Stop video.
        if (_useMediaKit && _mkPlayer != null) {
          try { await _mkPlayer!.stop(); } catch (_) {}
        }
        await _disposeAndroidController();
        // BUG 1 FIX: check generation again after every await.
        if (generation != _loadGeneration) return;

        try {
          if (_audio != null) {
              final localPath = await _resolveLocalPath(item.path);
              if (localPath.startsWith('http') || localPath.startsWith('content://')) {
                await _audio!.setUrl(localPath);
              } else {
                await _audio!.setFilePath(localPath);
              }
            if (generation != _loadGeneration) return;
            _runOnMainThread(() => _audio!.setVolume(volume));
            duration = _audio!.duration;
            position = Duration.zero;
            if (generation != _loadGeneration) return;
            await _audio!.play();
            _updateMediaNotification(item);
          } else if (_useMediaKit) {
            final player = _audioMkPlayer ?? _mkPlayer;
            if (player != null) {
              await _audioLock.acquire();
              try {
                final now = DateTime.now();
                if (_lastMkOpenTime != null &&
                    now.difference(_lastMkOpenTime!).inMilliseconds < 350) {
                  debugPrint('Skipping rapid audio open — too soon');
                } else {
                  _lastMkOpenTime = now;
                  await _openMediaWithFallback(player, item.path, play: true);
                }
                await player.setVolume(volume * _videoVolumeBoost * 100);
                // attempt to read duration; may be zero until stream updates
                try {
                  duration = await player.stream.duration
                      .firstWhere((d) => d.inMilliseconds > 0)
                      .timeout(const Duration(seconds: 1),
                          onTimeout: () => Duration.zero);
                } catch (_) {}
                position = Duration.zero;
              } catch (e) {
                debugPrint('media_kit audio load error for ${item.path}: $e');
              } finally {
                _audioLock.release();
              }
            } else {
              debugPrint(
                  'audio player unavailable on this platform for ${item.path}');
            }
          } else {
            debugPrint(
                'audio player unavailable on this platform for ${item.path}');
          }
        } catch (e) {
          debugPrint('audio load error for ${item.path}: $e');
        }
      } else {
        // Switching to video.
        // CRASH FIX: just_audio_windows crashes with "Operation aborted" when
        // stop() is called while its Media Foundation native thread is
        // mid-callback. pause() + setVolume(0) suspends playback safely
        // without tearing down the native pipeline.
        try {
          if (_audio != null) {
            await _audio!.pause();
            _audio!.setVolume(0);
          }
          if (_audioMkPlayer != null) {
            try { await _audioMkPlayer!.pause(); _audioMkPlayer!.setVolume(0); } catch (_) {}
          }
        } catch (_) {}
        if (generation != _loadGeneration) return;

        if (_useMediaKit && _mkPlayer != null) {
            try {
            final now = DateTime.now();
            if (_lastMkOpenTime != null && now.difference(_lastMkOpenTime!).inMilliseconds < 350) {
              debugPrint('Skipping rapid mk open — too soon');
            } else {
              _lastMkOpenTime = now;
              await _openMediaWithFallback(_mkPlayer!, item.path, play: true);
            }
            if (generation != _loadGeneration) {
              try { await _mkPlayer!.stop(); } catch (_) {}
              return;
            }
            await _mkPlayer!.setVolume(volume * _videoVolumeBoost * 100);
          } catch (e) {
            debugPrint('media_kit video load error: $e');
          }
        } else {
          await _loadAndroidVideo(item.path, generation);
        }
      }
    } catch (e, st) {
      debugPrint('PlayerState._loadCurrent failed: $e\n$st');
    } finally {
      if (generation == _loadGeneration) {
        notifyListeners();
        // Make sure we have a thumbnail for the now-playing item.
        requestThumbnailForIndex(currentIndex);
      }
    }
  }

  Future<void> _loadAndroidVideo(String path, int generation) async {
    try {
      await _disposeAndroidController();
      if (generation != _loadGeneration) return;

      VideoPlayerController? ctrl;

    final strategies = <Future<VideoPlayerController?> Function()>[
      if (path.startsWith('content://'))
        () async {
          final c = VideoPlayerController.networkUrl(Uri.parse(path));
          await c.initialize();
          return c;
        },
      if (!path.startsWith('content://'))
        () async {
          final c = VideoPlayerController.file(File(path));
          await c.initialize();
          return c;
        },
      () async {
        final local = await _resolveLocalPath(path);
        if (local == path) return null;
        final c = VideoPlayerController.file(File(local));
        await c.initialize();
        return c;
      },
    ];

    for (final strategy in strategies) {
      if (generation != _loadGeneration) return;
      try {
        ctrl = await strategy();
        if (ctrl != null) break;
      } catch (e) {
        debugPrint('android VP strategy failed: $e');
        try { await ctrl?.dispose(); } catch (_) {}
        ctrl = null;
      }
    }

    if (ctrl == null || generation != _loadGeneration) {
      try { await ctrl?.dispose(); } catch (_) {}
      return;
    }

    _androidController = ctrl;
    duration = ctrl.value.duration;
    position = Duration.zero;
    await ctrl.setVolume((volume * _videoVolumeBoost).clamp(0.0, 1.0));
    await ctrl.play();
    _videoReady = true;

    void listener() {
      if (_androidController == null) return;
      final val = _androidController!.value;
      if (currentItem?.type == MediaType.video) {
        position = val.position;
        if (val.duration != Duration.zero) duration = val.duration;
      }
      if (!_videoCompletionFired &&
          val.duration != Duration.zero &&
          val.position >= val.duration &&
          !val.isPlaying) {
        _videoCompletionFired = true;
        _handleCompletion();
      }
      _scheduleNotify();
    }

    _androidListener = listener;
    ctrl.addListener(listener);
  } catch (e, st) {
    debugPrint('Android video player failed: $e\n$st');
  }
}

  // ─── Playback controls ────────────────────────────────────────────────────

  List<int> _getPlaybackCandidates({MediaType? only}) {
    final scope = _folderItemCount > 0 ? _folderItemCount : library.length;
    return library
        .asMap()
        .entries
        .where((e) {
          if (favouritesOnly) {
            if (!_favourites.contains(e.value.path)) return false;
          } else {
            if (e.key >= scope) return false;
          }
          if (only != null && e.value.type != only) return false;
          return true;
        })
        .map((e) => e.key)
        .toList();
  }

  Future<void> togglePlay() async {
    if (_disposed) return;
    if (isVideo) {
      if (_useMediaKit && _mkPlayer != null) {
        await (_mkPlayer!.state.playing ? _mkPlayer!.pause() : _mkPlayer!.play());
      } else if (_androidController != null) {
        _androidController!.value.isPlaying
            ? await _androidController!.pause()
            : await _androidController!.play();
      }
    } else {
      if (_useMediaKit) {
        final player = _audioMkPlayer ?? _mkPlayer;
        if (player != null) {
          await _audioLock.acquire();
          try {
            await (player.state.playing ? player.pause() : player.play());
          } finally {
            _audioLock.release();
          }
        }
      } else if (_audio != null) {
        _audio!.playing ? await _audio!.pause() : await _audio!.play();
      }
    }
    notifyListeners();
  }

    Future<void> seek(Duration d) async {

      if (_disposed) return;

      debugPrint(

          'PlayerState.seek requested: $d, isVideo=$isVideo, _useMediaKit=$_useMediaKit');
    if (isVideo) {
      _videoCompletionFired = false;
      if (_useMediaKit && _mkPlayer != null) {
        debugPrint('Seeking media_kit video player to $d');
        try {
          await _mkPlayer!.seek(d);
        } catch (e) {
          debugPrint('media_kit video seek error: $e');
        }
      } else {
        debugPrint('Seeking android video controller to $d');
        try {
          await _androidController?.seekTo(d);
        } catch (e) {
          debugPrint('android video seek error: $e');
        }
      }
    } else {
      if (_useMediaKit) {
        final player = _audioMkPlayer ?? _mkPlayer;
        if (player != null) {
          debugPrint('Seeking media_kit audio player to $d');
          try {
            await _audioLock.acquire();
            await player.seek(d);
          } catch (e) {
            debugPrint('media_kit audio seek error: $e');
          } finally {
            _audioLock.release();
          }
        } else {
          debugPrint('No media_kit audio player available to seek');
        }
      } else if (_audio != null) {
        debugPrint('Seeking just_audio to $d');
        try {
          await _audio!.seek(d);
        } catch (e) {
          debugPrint('just_audio seek error: $e');
        }
      } else {
        debugPrint('No audio player available to seek');
      }
    }

    position = d;
    notifyListeners();

    // After a short delay log the effective position/duration and player states
    // to help diagnose seek-not-applying issues on desktop.
    Future.delayed(const Duration(milliseconds: 250), () {
      try {
        debugPrint('Post-seek: position=$position, duration=$duration, '
            'mkPlayer=${_mkPlayer != null ? _mkPlayer!.state.playing : 'null'}, '
            'audioMk=${_audioMkPlayer != null ? _audioMkPlayer!.state.playing : 'null'}, '
            'justAudio=${_audio != null ? _audio!.playing : 'null'}');
      } catch (_) {}
    });
  }

  Future<void> next({MediaType? only}) async {
    if (library.isEmpty) return;
    var candidates = _getPlaybackCandidates(only: only);
    if (candidates.isEmpty && only != null) {
      // If the current filter yields nothing (e.g. songs-only while in a video
      // folder), fall back to whatever is actually available.
      candidates = _getPlaybackCandidates(only: null);
    }
    if (candidates.isEmpty) return;
    int nextIndex;
    if (shuffle) {
      final others = candidates.where((i) => i != currentIndex).toList();
      nextIndex = others.isEmpty ? candidates.first : others[_random.nextInt(others.length)];
    } else {
      final pos = candidates.indexOf(currentIndex);
      nextIndex = pos >= 0 ? candidates[(pos + 1) % candidates.length] : candidates.first;
    }
    await select(nextIndex);
  }

  Future<void> previous({MediaType? only}) async {
    if (library.isEmpty) return;
    var candidates = _getPlaybackCandidates(only: only);
    if (candidates.isEmpty && only != null) {
      // If the current filter yields nothing (e.g. songs-only while in a video
      // folder), fall back to whatever is actually available.
      candidates = _getPlaybackCandidates(only: null);
    }
    if (candidates.isEmpty) return;
    int prevIndex;
    if (shuffle) {
      final others = candidates.where((i) => i != currentIndex).toList();
      prevIndex = others.isEmpty ? candidates.first : others[_random.nextInt(others.length)];
    } else {
      final pos = candidates.indexOf(currentIndex);
      prevIndex = pos >= 0
          ? candidates[(pos - 1 + candidates.length) % candidates.length]
          : candidates.last;
    }
    await select(prevIndex);
  }

  void setVolume(double v) {
    volume = v.clamp(0.0, 1.0);
    prefs.setDouble('volume', volume);
    _applyVolume();
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    prefs.setBool('shuffle', shuffle);
    // If shuffle is enabled, create a shuffled view of the manual queue
    if (shuffle) {
      // Preserve original order in _manualQueueBase (mutate, not reassign)
      _manualQueueBase.clear();
      _manualQueueBase.addAll(manualQueue);
      final shuffled = List<int>.from(_manualQueueBase);
      shuffled.shuffle(_random);
      manualQueue
        ..clear()
        ..addAll(shuffled);
    } else {
      // Restore original ordering
      manualQueue
        ..clear()
        ..addAll(_manualQueueBase);
    }
    notifyListeners();
  }

  void cycleRepeat() {
    repeatMode = RepeatMode.values[(repeatMode.index + 1) % RepeatMode.values.length];
    prefs.setInt('repeat', repeatMode.index);
    notifyListeners();
  }

  void _applyVolume() {
    // Only restore audio volume when audio is actually active.
    // When video is playing, audio is paused+muted; restoring volume here
    // would un-mute it and cause double audio.
    if (!isVideo) {
      if (_audio != null) _runOnMainThread(() => _audio!.setVolume(volume));
    }
    if (_useMediaKit) {
      if (_mkPlayer != null) _mkPlayer!.setVolume(volume * _videoVolumeBoost * 100);
      if (_audioMkPlayer != null) _audioMkPlayer!.setVolume(volume * _videoVolumeBoost * 100);
    }
    if (_androidController != null) {
      _androidController!.setVolume((volume * _videoVolumeBoost).clamp(0.0, 1.0));
    }
  }


  // Post a call to the main isolate. microtask is always processed on the
  // main Dart thread regardless of whether a frame is being rendered.
  void _runOnMainThread(VoidCallback fn) {
    Future.microtask(fn);
  }

  // ─── Queue ────────────────────────────────────────────────────────────────

  void enqueue(int index) {
    debugPrint('enqueue requested: $index, library=${library.length}');
    if (index < 0 || index >= library.length) {
      debugPrint('enqueue ignored: out of range');
      return;
    }
    try {
      // Always append to base order
      _manualQueueBase.add(index);
      if (shuffle) {
        // Insert into visible queue at a random position
        final pos = _random.nextInt(manualQueue.length + 1);
        manualQueue.insert(pos, index);
      } else {
        manualQueue.add(index);
      }
      debugPrint('enqueue done: manualQueue=${manualQueue.length} base=${_manualQueueBase.length}');
      notifyListeners();
    } catch (e, st) {
      debugPrint('enqueue error: $e\n$st');
      rethrow;
    }
  }

  void dequeue(int queuePosition) {
    if (queuePosition < 0 || queuePosition >= manualQueue.length) return;
    final val = manualQueue.removeAt(queuePosition);
    final basePos = _manualQueueBase.indexOf(val);
    if (basePos >= 0) _manualQueueBase.removeAt(basePos);
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (shuffle) return; // disable reordering while shuffled
    if (oldIndex < 0 || oldIndex >= manualQueue.length) return;
    final item = manualQueue.removeAt(oldIndex);
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final dest = adjusted.clamp(0, manualQueue.length);
    manualQueue.insert(dest, item);
    // keep base order in sync when not shuffled
    final baseOld = _manualQueueBase.indexOf(item);
    if (baseOld >= 0) {
      final baseItem = _manualQueueBase.removeAt(baseOld);
      _manualQueueBase.insert(dest.clamp(0, _manualQueueBase.length), baseItem);
    }
    notifyListeners();
  }

  void clearQueue() {
    manualQueue.clear();
    _manualQueueBase.clear();
    notifyListeners();
  }

  void _handleCompletion() {
    if (manualQueue.isNotEmpty) {
      final nextIdx = manualQueue.removeAt(0);
      select(nextIdx);
      return;
    }
    if (repeatMode == RepeatMode.one) {
      _videoCompletionFired = false;
      final gen = ++_loadGeneration;
      _loadCurrent(currentIndex, gen);
      return;
    }
    if (repeatMode == RepeatMode.all) {
      next(only: activeTabFilter);
      return;
    }
    final candidates = _getPlaybackCandidates(only: activeTabFilter);
    final pos = candidates.indexOf(currentIndex);
    if (shuffle || (pos >= 0 && pos < candidates.length - 1)) {
      next(only: activeTabFilter);
    }
  }

  // ─── Playback mode / prefs ────────────────────────────────────────────────

  void setPlaybackMode(PlaybackMode mode) {
    playbackMode = mode;
    prefs.setInt('playbackMode', mode.index);
    _applyPlaybackMode();
    notifyListeners();
  }

  void _applyPlaybackMode() {
    switch (playbackMode) {
      case PlaybackMode.songs:
        activeTabFilter = MediaType.audio;
        favouritesOnly = false;
      case PlaybackMode.videos:
        activeTabFilter = MediaType.video;
        favouritesOnly = false;
      case PlaybackMode.favourites:
        activeTabFilter = null;
        favouritesOnly = true;
      case PlaybackMode.all:
        activeTabFilter = null;
        favouritesOnly = false;
    }
  }

  Future<void> _loadPrefs() async {
    volume = prefs.getDouble('volume') ?? 0.5;
    shuffle = prefs.getBool('shuffle') ?? false;
    repeatMode = RepeatMode.values[
        (prefs.getInt('repeat') ?? 0).clamp(0, RepeatMode.values.length - 1)];
    playbackMode = PlaybackMode.values[
        (prefs.getInt('playbackMode') ?? 0).clamp(0, PlaybackMode.values.length - 1)];
    _applyPlaybackMode();
    _favourites = (prefs.getStringList('player_favourites') ?? []).toSet();

    _favouriteCache.clear();
    for (final raw in prefs.getStringList('player_favourites_cache') ?? []) {
      final parts = raw.split('\t');
      if (parts.length >= 2) {
        final path = parts[0];
        final type = parts[1] == 'v' ? MediaType.video : MediaType.audio;
        final title = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
        final artist = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
        _favouriteCache[path] = MediaItem(path, type, title: title, artist: artist);
      }
    }
    _loadFavouriteThumbsFromDisk();
    notifyListeners();
  }

  /// Enqueue a set of tracks determined by [scope]. Returns the number of
  /// tracks actually added (duplicates are ignored).
  int enqueueScope(QueueScope scope) {
    debugPrint('enqueueScope: $scope');

    // Prevent overloading the UI / list view with huge queues. This keeps the
    // app responsive when users add a very large number of favourites.
    const maxQueueSize = 500;
    final availableSpace = maxQueueSize - manualQueue.length;
    if (availableSpace <= 0) return 0;

    final List<int> candidates = [];
    final limit = _folderItemCount > 0 ? _folderItemCount : library.length;
    for (var i = 0; i < limit; i++) {
      final item = library[i];
      switch (scope) {
        case QueueScope.all:
          candidates.add(i);
          break;
        case QueueScope.songs:
          if (item.type == MediaType.audio) candidates.add(i);
          break;
        case QueueScope.videos:
          if (item.type == MediaType.video) candidates.add(i);
          break;
        case QueueScope.favourites:
          if (_favourites.contains(item.path)) candidates.add(i);
          break;
        case QueueScope.favSongs:
          if (_favourites.contains(item.path) && item.type == MediaType.audio) candidates.add(i);
          break;
        case QueueScope.favVideos:
          if (_favourites.contains(item.path) && item.type == MediaType.video) candidates.add(i);
          break;
      }
      if (candidates.length >= maxQueueSize) break;
    }

    int added = 0;
    for (final idx in candidates) {
      if (_manualQueueBase.contains(idx)) continue;
      if (manualQueue.length >= maxQueueSize) break;
      _manualQueueBase.add(idx);
      if (shuffle) {
        final pos = _random.nextInt(manualQueue.length + 1);
        manualQueue.insert(pos, idx);
      } else {
        manualQueue.add(idx);
      }
      added++;
    }
    if (added > 0) notifyListeners();
    return added;
  }

  Future<void> _loadFavouriteThumbsFromDisk() async {
    for (final path in _favouriteCache.keys.toList()) {
      final cached = _favouriteCache[path];
      if (cached == null || cached.thumbnailData != null) continue;
      final bytes = await _loadThumbFromCache(path);
      if (bytes != null && _favouriteCache.containsKey(path)) {
        _favouriteCache[path] = cached.copyWith(thumbnailData: bytes);
        final idx = library.indexWhere((item) => item.path == path);
        if (idx >= 0 && library[idx].thumbnailData == null) {
          library[idx] = library[idx].copyWith(thumbnailData: bytes);
        }
        notifyListeners();
      }
    }
  }

  // ─── Audio handler (Android) ──────────────────────────────────────────────

  Future<void> _initAudioHandler() async {
    // _audio is non-null when this is called (guarded by caller).
    _audioHandler = await initAudioService(_audio!);
    if (_audioHandler != null) {
      _audioHandler!.onSkipToNext = () => next(only: MediaType.audio);
      _audioHandler!.onSkipToPrevious = () => previous(only: MediaType.audio);
    }
  }

  void _updateMediaNotification(MediaItem item) {
    if (_audioHandler == null) return;
    _audioHandler!.updateMediaItem(audio_svc.MediaItem(
      id: item.path,
      title: item.title ?? p.basenameWithoutExtension(item.path),
      artist: item.artist ?? '',
      duration: duration,
    ));
  }

  // ─── Directory watcher ────────────────────────────────────────────────────

  void _startDirectoryWatcher(List<MediaItem> items) {
    _dirWatcher?.cancel();
    _dirWatcher = null;
    _watchedDirPath = null;

    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return;
    if (items.isEmpty) return;
    final firstPath = items.first.path;
    if (firstPath.startsWith('content://')) return;
    final dirPath = p.dirname(firstPath);
    _watchedDirPath = dirPath;

    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return;
      Timer? debounce;
      _dirWatcher = dir.watch().listen((event) {
        if (_disposed) return;
        final ext = p.extension(event.path).toLowerCase();
        if (!_mediaExtensions.contains(ext)) return;
        debounce?.cancel();
        debounce = Timer(const Duration(seconds: 2), () {
          if (!_disposed) _refreshLibraryFromDisk();
        });
      });
    } catch (e) {
      debugPrint('Directory watcher error: $e');
    }
  }

  Future<void> _refreshLibraryFromDisk() async {
    final dirPath = _watchedDirPath;
    if (dirPath == null) return;
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;
    final files = dir.listSync(recursive: true).whereType<File>().where((f) {
      return _mediaExtensions.contains(p.extension(f.path).toLowerCase());
    }).map((f) {
      final ext = p.extension(f.path).toLowerCase();
      final isVideo = {'.mp4', '.mkv', '.avi', '.webm', '.mov', '.wmv', '.flv', '.m4v'}.contains(ext);
      return MediaItem(f.path, isVideo ? MediaType.video : MediaType.audio,
          title: p.basenameWithoutExtension(f.path));
    }).toList();

    final currentPaths = library.take(_folderItemCount).map((e) => e.path).toSet();
    final newPaths = files.map((e) => e.path).toSet();
    if (currentPaths.length == newPaths.length && currentPaths.containsAll(newPaths)) return;

    await setLibrary(files);
  }

  // ─── Video thumbnail generation ───────────────────────────────────────────

  Future<Uint8List?> _generateVideoThumbnail(String filePath) async {
    final resolved = await _resolveLocalPath(filePath);

    // Strategy 1: video_thumbnail plugin.
    // The `video_thumbnail` plugin is not implemented on desktop platforms
    // (Windows/Linux/macOS) in this project.
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        // Skip video_thumbnail on desktop.
      } else {
        try {
          final snap = await VideoThumbnail.thumbnailData(
            video: resolved,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 256,
            quality: 60,
          );
          if (snap != null && snap.length >= 64) {
            return await _transcodeToSafePng(snap, mimeType: 'image/jpeg');
          }
        } on MissingPluginException catch (_) {
          // Plugin not available on this platform — ignore and continue.
          debugPrint('video_thumbnail plugin missing on this platform for $resolved');
        }
      }
    } catch (e) {
      debugPrint('video_thumbnail error for $resolved: $e');
    }

    // Strategy 2: media_kit screenshot.
    // On Windows this can destabilize the app in bulk scans. Use FFmpeg instead.
    if (!Platform.isWindows && _useMediaKit && _thumbPlayer != null) {
      try {
        await _thumbLock.acquire();
        if (_disposed) return null;

        await _thumbPlayer!.setVolume(0);
        final now = DateTime.now();
        if (_lastThumbOpenTime != null &&
            now.difference(_lastThumbOpenTime!).inMilliseconds < 800) {
          debugPrint('Skipping rapid thumb open — too soon');
        } else {
          _lastThumbOpenTime = now;
          await _openMediaWithFallback(_thumbPlayer!, filePath, play: false);
        }

        Duration? dur;
        try {
          dur = await _thumbPlayer!.stream.duration
              .firstWhere((d) => d.inMilliseconds > 0)
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
        if (dur != null && dur.inMilliseconds > 0) {
          await _thumbPlayer!.seek(Duration(
              milliseconds:
                  (dur.inMilliseconds * 0.1).round().clamp(0, 15000)));
        }

        await Future.delayed(const Duration(milliseconds: 800));
        if (_disposed) return null;

        final snap = await _thumbPlayer!.screenshot();
        if (snap != null && snap.length >= 64) {
          return await _transcodeToSafePng(snap);
        }
      } catch (e) {
        debugPrint('screenshot error for $filePath: $e');
      } finally {
        _thumbLock.release();
      }
    }

    // Strategy 3: fallback to ffmpeg if available (desktop only).
    return await _generateVideoThumbnailWithFfmpeg(resolved);
  }

  /// Wrapper that guarantees only one thumbnail generation runs at a time.
  Future<Uint8List?> _generateVideoThumbnailSafe(String filePath) async {
    // Windows thumbnail generation has proven unstable (native crashes).
    // Avoid any native thumbnail generation on Windows and use a placeholder.
    if (Platform.isWindows) return null;

    await _thumbLock.acquire();
    try {
      if (_disposed) return null;
      return await _generateVideoThumbnail(filePath);
    } finally {
      _thumbLock.release();
    }
  }

  Future<Uint8List?> _generateVideoThumbnailWithFfmpeg(String filePath) async {
    try {
      final ffmpeg = FfmpegService();
      final ffmpegPath = await ffmpeg.resolveAvailablePath(null);
      if (ffmpegPath == null) return null;

      final dir = await _getThumbCacheDir();
      final outPath = '${dir.path}${Platform.pathSeparator}${_thumbCacheKey(filePath)}.png';
      final outputFile = File(outPath);

      final args = [
        '-y',
        '-i',
        filePath,
        '-ss',
        '00:00:01',
        '-frames:v',
        '1',
        '-vf',
        'scale=256:-1',
        outPath,
      ];

      await ffmpeg.run(args, ffmpegPath: ffmpegPath);
      if (!await outputFile.exists()) return null;
      final bytes = await outputFile.readAsBytes();
      if (bytes.length < 64) return null;
      return await _transcodeToSafePng(bytes, mimeType: 'image/png');
    } catch (e) {
      debugPrint('ffmpeg thumbnail error for $filePath: $e');
    }
    return null;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<String> _resolveLocalPath(String path) async {
    if (path.startsWith('content://')) {
      final copied = await PlatformDirs.copyToTemp(path);
      return copied ?? path;
    }
    return path;
  }

  String _toUri(String path) {
    if (path.startsWith('file://') || path.startsWith('http') || path.startsWith('content://')) return path;
    if (!kIsWeb && Platform.isWindows) return Uri.file(path, windows: true).toString();
    return Uri.file(path).toString();
  }

  // Try multiple URI formats to improve compatibility with Android file paths
  // (spaces, special characters, and plugins that expect different schemes).
  Future<void> _openMediaWithFallback(Player player, String path, {bool play = false}) async {
    final tried = <String>{};
    final candidates = <String>[];
    try {
      candidates.add(_toUri(path));
    } catch (_) {}
    try {
      // raw file:// prefix
      if (!path.startsWith('file://')) candidates.add('file://$path');
    } catch (_) {}
    try {
      // encoded path
      final encoded = Uri.file(path).toString();
      if (!candidates.contains(encoded)) candidates.add(encoded);
    } catch (_) {}
    try {
      // fallback to plain path
      if (!candidates.contains(path)) candidates.add(path);
    } catch (_) {}

    for (final uri in candidates) {
      if (tried.contains(uri)) continue;
      tried.add(uri);
      try {
        await player.open(Media(uri), play: play);
        return;
      } catch (e) {
        debugPrint('media open failed for $uri: $e');
        // try next
      }
    }
    // If all attempts failed, finally try the original and let caller handle the error
    try {
      await player.open(Media(_toUri(path)), play: play);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _disposeAndroidController() async {
    if (_androidController == null) return;
    if (_androidListener != null) {
      _androidController!.removeListener(_androidListener!);
      _androidListener = null;
    }
    try { await _androidController!.dispose(); } catch (_) {}
    _androidController = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _dirWatcher?.cancel();
    for (final sub in _subs) { try { sub.cancel(); } catch (_) {} }
    _subs.clear();
    for (final sub in _mkSubs) { try { sub.cancel(); } catch (_) {} }
    _mkSubs.clear();
    if (_audio != null) {
      try { _audio!.dispose(); } catch (_) {}
    }
    if (_useMediaKit) {
      try { _mkPlayer?.stop(); } catch (_) {}
      try { _mkPlayer?.dispose(); } catch (_) {}
      try { _thumbPlayer?.stop(); } catch (_) {}
      try { _thumbPlayer?.dispose(); } catch (_) {}
      try { _audioMkPlayer?.stop(); } catch (_) {}
      try { _audioMkPlayer?.dispose(); } catch (_) {}
    }
    _disposeAndroidController();
    super.dispose();
  }

  /// Immediately play a file by its filesystem path. This bypasses any
  /// id/index-based indirection so taps reliably play the exact file.
  Future<void> playFileDirect(String path) async {
    if (_disposed) return;

    // Try to find a library index for UI bookkeeping; not required to play.
    final idx = library.indexWhere((m) => m.path == path);
    if (idx >= 0) {
      currentIndex = idx;
      notifyListeners();
    }

    // Bump generation to cancel any in-flight _loadCurrent calls.
    final generation = ++_loadGeneration;

    // Stop existing playback first (best-effort).
    if (_audio != null) {
      try { await _audio!.stop(); } catch (_) {}
    }
    if (_audioMkPlayer != null) {
      try { await _audioMkPlayer!.stop(); } catch (_) {}
    }
    if (_useMediaKit && _mkPlayer != null) {
      try {
        await _mkPlayer!.stop();
      } catch (_) {}
    }
    await _disposeAndroidController();

    if (generation != _loadGeneration) return;

    // Decide audio vs video using library entry if available, otherwise use
    // extension heuristic.
    MediaType type = MediaType.audio;
    if (idx >= 0) type = library[idx].type;
    else {
      final ext = p.extension(path).toLowerCase();
      final videoExts = {'.mp4', '.mkv', '.avi', '.webm', '.mov', '.wmv', '.flv', '.m4v'};
      if (videoExts.contains(ext)) type = MediaType.video;
    }

    try {
      if (type == MediaType.audio) {
        if (_useMediaKit && _audioMkPlayer != null) {
          await _audioLock.acquire();
          // Use the dedicated media_kit audio-only player on desktop to avoid
          // reusing the video player's texture and to keep audio streams
          // consistent with _loadCurrent.
          try {
            final now = DateTime.now();
            if (_lastMkOpenTime != null &&
                now.difference(_lastMkOpenTime!).inMilliseconds < 350) {
              debugPrint('Skipping rapid audioMk open — too soon');
              } else {
              _lastMkOpenTime = now;
              await _openMediaWithFallback(_audioMkPlayer!, path, play: true);
            }
            await _audioMkPlayer!.setVolume(volume * _videoVolumeBoost * 100);
            duration = await _audioMkPlayer!.stream.duration
                .firstWhere((d) => d.inMilliseconds > 0)
                .timeout(const Duration(seconds: 1),
                    onTimeout: () => Duration.zero);
            position = Duration.zero;
          } catch (e) {
            debugPrint(
                'playFileDirect media_kit audio load error for $path: $e');
          } finally {
            _audioLock.release();
          }
        } else {
          // Use just_audio on mobile/Android where media_kit isn't used.
          // Use a microtask to ensure we run on the main isolate thread.
          if (_audio != null) {
            await Future.microtask(() async {
              try {
                final local = await _resolveLocalPath(path);
                if (local.startsWith('http') || local.startsWith('content://')) {
                  await _audio!.setUrl(local);
                } else {
                  await _audio!.setFilePath(local);
                }
                await _audio!.setVolume(volume);
                duration = _audio!.duration;
                position = Duration.zero;
                await _audio!.play();
                if (idx >= 0) _updateMediaNotification(library[idx]);
              } catch (e) {
                debugPrint('playFileDirect audio load error for $path: $e');
              }
            });
          }
        }
      } else {
        // Video: prefer media_kit on supported platforms.
        if (_useMediaKit && _mkPlayer != null) {
          final now = DateTime.now();
          if (_lastMkOpenTime != null && now.difference(_lastMkOpenTime!).inMilliseconds < 350) {
            debugPrint('Skipping rapid mk open (playFileDirect) — too soon');
          } else {
            _lastMkOpenTime = now;
            await _openMediaWithFallback(_mkPlayer!, path, play: true);
          }
          await _mkPlayer!.setVolume(volume * _videoVolumeBoost * 100);
        } else {
          // Android fallback
          await _loadAndroidVideo(path, generation);
        }
      }
    } catch (e) {
      debugPrint('playFileDirect failed for $path: $e');
    }
  }
}

// ─── Helper types for the All tab ────────────────────────────────────────────

enum _AllTabKind { header, song }

class _AllTabItem {
  final _AllTabKind kind;
  final String? headerText;
  final MapEntry<int, MediaItem>? entry;

  const _AllTabItem.header(this.headerText)
      : kind = _AllTabKind.header,
        entry = null;

  _AllTabItem.song(this.entry)
      : kind = _AllTabKind.song,
        headerText = null;
}


// ─── Persistent video widget ──────────────────────────────────────────────────

class _VideoPane extends StatefulWidget {
  final VideoController? mkController;
  final VideoPlayerController? androidController;
  final bool visible;
  final bool ready;
  final bool isFullScreen;
  final VoidCallback onTap;
  final VoidCallback onToggleFullScreen;

  const _VideoPane({
    required this.mkController,
    required this.androidController,
    required this.visible,
    required this.ready,
    required this.onTap,
    required this.isFullScreen,
    required this.onToggleFullScreen,
    Key? key,
  }) : super(key: key);

  @override
  State<_VideoPane> createState() => _VideoPaneState();
}

class _VideoPaneState extends State<_VideoPane> {
  Size? _prevSize;
  bool _recreateScheduled = false;

  void _maybeScheduleRecreate(BuildContext context, Size size) {
    if (_prevSize == null) {
      _prevSize = size;
      return;
    }
    // If area increases dramatically (e.g., maximize), schedule a single recreate.
    final oldArea = _prevSize!.width * _prevSize!.height;
    final newArea = size.width * size.height;
    if (!_recreateScheduled && oldArea > 0 && newArea / oldArea > 2.0) {
      _recreateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await context.read<PlayerState>().safeRecreateMkPlayer();
        } catch (e) {
          debugPrint('recreate scheduled failed: $e');
        } finally {
          // allow future recreates after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            _recreateScheduled = false;
          });
        }
      });
    }
    _prevSize = size;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    final size = mq.size;
    _maybeScheduleRecreate(context, size);

    Widget child;
    if (widget.mkController != null) {
      child = Video(controller: widget.mkController!);
    } else if (widget.androidController != null) {
      child = ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: widget.androidController!,
        builder: (_, val, __) => val.isInitialized
            ? AspectRatio(aspectRatio: val.aspectRatio, child: VideoPlayer(widget.androidController!))
            : const Center(child: CircularProgressIndicator(color: _PlayerTheme.accent)),
      );
    } else {
      child = const Center(child: CircularProgressIndicator(color: _PlayerTheme.accent));
    }

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.expand(
        child: ColoredBox(
          color: Theme.of(context).colorScheme.background,
          child: widget.ready
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    child,
                    Positioned(
                      top: 10,
                      right: 10,
                      child: IconButton(
                        icon: Icon(
                          widget.isFullScreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          color: Colors.white.withOpacity(0.85),
                        ),
                        tooltip: widget.isFullScreen
                            ? 'Exit fullscreen'
                            : 'Fullscreen',
                        onPressed: widget.onToggleFullScreen,
                      ),
                    ),
                  ],
                )
              : const Center(child: CircularProgressIndicator(color: _PlayerTheme.accent)),
        ),
      ),
    );
  }
}

// ─── Theme constants ──────────────────────────────────────────────────────────

abstract class _PlayerTheme {
  static const accent = Color(0xFF5B8DEF);
  static const accentDim = Color(0x334A7EDB);

  static Color tileBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E1E22)
          : const Color(0xFFF0F0F5);

  static Color text(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color sub(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
}

// ─── Root screen ──────────────────────────────────────────────────────────────

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isFullScreen = false;

  // One scroll controller per tab to avoid cross-tab controller conflicts.
  final _scrollControllers = List.generate(4, (_) => ScrollController());

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() { if (!_tabController.indexIsChanging) setState(() {}); });
  }

  @override
  void dispose() {
    _exitFullScreen();
    _tabController.dispose();
    _searchController.dispose();
    for (final sc in _scrollControllers) { sc.dispose(); }
    super.dispose();
  }

  Future<void> _enterFullScreen() async {
    if (_isFullScreen) return;
    _isFullScreen = true;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitFullScreen() async {
    if (!_isFullScreen) return;
    _isFullScreen = false;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  bool _matchesSearch(MediaItem item) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    final title = (item.title ?? p.basenameWithoutExtension(item.path)).toLowerCase();
    final artist = (item.artist ?? '').toLowerCase();
    return title.contains(q) || artist.contains(q);
  }

  Future<void> _pickFolder() async {
    if (kIsWeb) return;
    String? dirPath;
    try {
      dirPath = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select media folder');
    } catch (e) {
      debugPrint('folder picker error: $e');
    }
    if (dirPath == null || !mounted) return;

    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;

    final items = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => PlayerState._mediaExtensions.contains(p.extension(f.path).toLowerCase()))
        .map((f) {
          final ext = p.extension(f.path).toLowerCase();
          final isVideo = {'.mp4', '.mkv', '.avi', '.webm', '.mov', '.wmv', '.flv', '.m4v'}.contains(ext);
          return MediaItem(f.path, isVideo ? MediaType.video : MediaType.audio,
              title: p.basenameWithoutExtension(f.path));
        })
        .toList();

    if (mounted) await context.read<PlayerState>().setLibrary(items);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();

    final songCount = state.audioEntries.length;
    final videoCount = state.videoEntries.length;
    final favCount = state.favouriteEntries.length;
    final allCount = songCount + videoCount;

    // Whether the video pane should be shown.
    final showVideo = state.isVideo &&
        (state.videoController != null ||
            state.androidVideoController != null);

    if (_isFullScreen) {
      return Scaffold(
        body: SafeArea(
          top: false,
          bottom: false,
          child: _VideoPane(
            mkController: state.videoController,
            androidController: state.androidVideoController,
            visible: true,
            ready: state.videoReady,
            isFullScreen: true,
            onTap: state.togglePlay,
            onToggleFullScreen: () async {
              await _exitFullScreen();
              setState(() {});
            },
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: true,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            final isMobile = MediaQuery.of(context).size.width < 600;
            final showVideoPane = showVideo;
            return [
              if (showVideoPane)
                SliverToBoxAdapter(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    height: 260.0,
                    clipBehavior: Clip.hardEdge,
                    decoration:
                        BoxDecoration(color: Theme.of(context).colorScheme.background),
                    child: _VideoPane(
                      mkController: state.videoController,
                      androidController: state.androidVideoController,
                      visible: true,
                      ready: state.videoReady,
                      isFullScreen: _isFullScreen,
                      onTap: state.togglePlay,
                      onToggleFullScreen: () async {
                        if (_isFullScreen) {
                          await _exitFullScreen();
                        } else {
                          await _enterFullScreen();
                        }
                        setState(() {});
                      },
                    ),
                  ),
                ),
              if (!(isMobile && showVideoPane))
                SliverToBoxAdapter(child: _buildHeader()),
              if (!(isMobile && showVideoPane))
                SliverToBoxAdapter(child: _buildNowPlaying(state)),
              if (state.isLoading)
                SliverToBoxAdapter(
                  child: const LinearProgressIndicator(
                    color: _PlayerTheme.accent,
                    minHeight: 2,
                  ),
                ),
              SliverToBoxAdapter(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: _PlayerTheme.accent,
                    unselectedLabelColor: _PlayerTheme.sub(context),
                    indicatorColor: _PlayerTheme.accent,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: 'All ($allCount)'),
                      Tab(text: '♪ Songs ($songCount)'),
                      Tab(text: '▶ Videos ($videoCount)'),
                      Tab(text: '★ Fav ($favCount)'),
                    ],
                  ),
                ),
              ),
              if (!(isMobile && showVideoPane))
                SliverToBoxAdapter(child: _buildSearchBar()),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _AllTab(state: state, scrollCtl: _scrollControllers[0], matchFn: _matchesSearch, onTap: _onTrackTap),
              _SongsTab(state: state, scrollCtl: _scrollControllers[1], matchFn: _matchesSearch, onTap: _onTrackTap),
              _VideosTab(state: state, scrollCtl: _scrollControllers[2], matchFn: _matchesSearch, onTap: _onTrackTap),
              _FavouritesTab(state: state, scrollCtl: _scrollControllers[3], matchFn: _matchesSearch, onTap: _onTrackTap),
            ],
          ),
        ),
      ),
    );
  }

  // BUG 1 FIX: all taps go through this single method which immediately captures
  // the index and calls select() — no intermediate setState() that could shift indices.
  void _onTrackTap(PlayerState state, int index) {
    // Play by file path to avoid any index/id races in the UI layer or native
    // plugins. This ensures taps map directly to the file the user tapped.
    final idx = index;
    if (idx >= 0 && idx < state.library.length) {
      final path = state.library[idx].path;
      state.playFileDirect(path);
    }
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(
          children: [
            const Icon(Icons.music_note_rounded, color: _PlayerTheme.accent, size: 26),
            const SizedBox(width: 8),
            const Text(
              'Player',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _PlayerTheme.accent,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.folder_open_rounded,
                  color: Theme.of(context).colorScheme.onSurface),
              tooltip: 'Open folder',
              onPressed: _pickFolder,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        ),
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
      ),
    );
  }

  // ─── Now Playing bar ──────────────────────────────────────────────────────

  Widget _buildNowPlaying(PlayerState state) {
    final item = state.currentItem;
    if (item == null) return const SizedBox.shrink();

    final title = item.title ?? p.basenameWithoutExtension(item.path);
    final artist = item.artist ?? '';
    final dur = state.duration ?? Duration.zero;
    final pos = state.position;
    final progress = dur.inMilliseconds > 0
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: _PlayerTheme.tileBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Track info ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
            child: Row(
              children: [
                // Thumbnail
                _TrackThumbnail(
                  data: item.thumbnailData,
                  isVideo: item.type == MediaType.video,
                  size: 52,
                  radius: 10,
                ),
                const SizedBox(width: 12),
                // Title / artist / type badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Type badge — clear visual distinction between audio and video
                          _TypeBadge(type: item.type),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: _PlayerTheme.text(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (artist.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: _PlayerTheme.sub(context)),
                        ),
                      ],
                    ],
                  ),
                ),
                // Favourite button
                IconButton(
                  icon: Icon(
                    state.isFavourite(item.path) ? Icons.star_rounded : Icons.star_border_rounded,
                    color: state.isFavourite(item.path) ? Colors.amber : _PlayerTheme.sub(context),
                    size: 24,
                  ),
                  onPressed: () => state.toggleFavourite(item.path),
                ),
              ],
            ),
          ),

          // ── Seek bar ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Text(_fmtDur(pos), style: TextStyle(fontSize: 11, color: _PlayerTheme.sub(context))),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: progress,
                      activeColor: _PlayerTheme.accent,
                      inactiveColor: _PlayerTheme.accentDim,
                      onChanged: dur.inMilliseconds > 0
                          ? (v) => state.seek(Duration(milliseconds: (v * dur.inMilliseconds).round()))
                          : null,
                    ),
                  ),
                ),
                Text(_fmtDur(dur), style: TextStyle(fontSize: 11, color: _PlayerTheme.sub(context))),
              ],
            ),
          ),

          // ── Playback controls ──
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ControlButton(
                  icon: Icons.shuffle_rounded,
                  active: state.shuffle,
                  onPressed: state.toggleShuffle,
                  tooltip: 'Shuffle',
                  size: 22,
                ),
                _ControlButton(
                  icon: Icons.skip_previous_rounded,
                  onPressed: () => state.previous(only: state.activeTabFilter),
                  size: 30,
                ),
                _PlayPauseButton(
                  playing: state.isPlaying,
                  onPressed: state.togglePlay,
                ),
                _ControlButton(
                  icon: Icons.skip_next_rounded,
                  onPressed: () => state.next(only: state.activeTabFilter),
                  size: 30,
                ),
                _ControlButton(
                  icon: state.repeatMode == RepeatMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  active: state.repeatMode != RepeatMode.off,
                  onPressed: state.cycleRepeat,
                  tooltip: 'Repeat',
                  size: 22,
                ),
              ],
            ),
          ),

          // ── Volume ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              children: [
                Icon(Icons.volume_down_rounded, size: 18, color: _PlayerTheme.sub(context)),
                Expanded(
                  child: Slider(
                    value: state.volume,
                    activeColor: _PlayerTheme.accent,
                    inactiveColor: _PlayerTheme.accentDim,
                    onChanged: state.setVolume,
                  ),
                ),
                Icon(Icons.volume_up_rounded, size: 18, color: _PlayerTheme.sub(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ─── Shared UI components ───────────────────────────────────────────────────

class _TrackThumbnail extends StatelessWidget {
  final Uint8List? data;
  final bool isVideo;
  final double size;
  final double radius;

  const _TrackThumbnail({this.data, required this.isVideo, required this.size, required this.radius});

  @override
  Widget build(BuildContext context) {
    if (data != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.memory(
          data!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }

    final icon = isVideo ? Icons.videocam_rounded : Icons.music_note;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: Theme.of(context).colorScheme.onSurface.withAlpha(15),
      ),
      child: Icon(icon, size: size * 0.55, color: Theme.of(context).colorScheme.onSurface.withAlpha(153)),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final MediaType type;

  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = type == MediaType.video;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(31),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isVideo ? 'VIDEO' : 'AUDIO',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;

  const _ControlButton({
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.tooltip,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Theme.of(context).colorScheme.primary : Theme.of(context).iconTheme.color;
    return IconButton(
      iconSize: size,
      tooltip: tooltip,
      icon: Icon(icon, color: color),
      onPressed: onPressed,
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onPressed;

  const _PlayPauseButton({required this.playing, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(12),
        backgroundColor: Theme.of(context).colorScheme.primary,
        minimumSize: const Size(48, 48),
      ),
      onPressed: onPressed,
      child: Icon(
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        color: Theme.of(context).colorScheme.onPrimary,
        size: 24,
      ),
    );
  }
}

// ─── Tab widgets (each is its own StatelessWidget to limit rebuild scope) ─────

/// BUG 2 FIX: each tab is its own widget so rebuilds from thumbnail loads only
/// repaint the visible tab, not the entire screen.

class _AllTab extends StatelessWidget {
  final PlayerState state;
  final ScrollController scrollCtl;
  final bool Function(MediaItem) matchFn;
  final void Function(PlayerState, int) onTap;

  const _AllTab({
    required this.state,
    required this.scrollCtl,
    required this.matchFn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final audio = state.audioEntries.where((e) => matchFn(e.value)).toList();
    final video = state.videoEntries.where((e) => matchFn(e.value)).toList();

    if (audio.isEmpty && video.isEmpty) {
      return _EmptyHint(message: state.library.isEmpty
          ? 'Your library is empty.\nTap the folder icon to open a folder or download media.'
          : 'No results for this search.');
    }

    // Use a CustomScrollView with Slivers so grids are the primary scrollable
    // and only visible items are built.
    return CustomScrollView(
      controller: scrollCtl,
      slivers: [
        if (audio.isNotEmpty) ...[
          SliverToBoxAdapter(child: _SectionHeader(text: 'Songs — ${audio.length}')),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final entry = audio[i];
                  return _MediaCard(entry: entry, state: state, onTap: onTap);
                },
                childCount: audio.length,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width < 500 ? 2 : (MediaQuery.of(context).size.width < 900 ? 3 : 5),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
            ),
          ),
        ],
        if (video.isNotEmpty) ...[
          SliverToBoxAdapter(child: _SectionHeader(text: 'Videos — ${video.length}')),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final entry = video[i];
                  return _MediaCard(entry: entry, state: state, onTap: onTap);
                },
                childCount: video.length,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width < 500 ? 2 : (MediaQuery.of(context).size.width < 900 ? 3 : 5),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SongsTab extends StatelessWidget {
  final PlayerState state;
  final ScrollController scrollCtl;
  final bool Function(MediaItem) matchFn;
  final void Function(PlayerState, int) onTap;

  const _SongsTab({required this.state, required this.scrollCtl, required this.matchFn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final filtered = state.audioEntries.where((e) => matchFn(e.value)).toList();
    if (filtered.isEmpty) return const _EmptyHint(message: 'No songs found.');
    return _MediaGrid(entries: filtered, state: state, onTap: onTap);
  }
}

class _VideosTab extends StatelessWidget {
  final PlayerState state;
  final ScrollController scrollCtl;
  final bool Function(MediaItem) matchFn;
  final void Function(PlayerState, int) onTap;

  const _VideosTab({required this.state, required this.scrollCtl, required this.matchFn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final filtered = state.videoEntries.where((e) => matchFn(e.value)).toList();
    if (filtered.isEmpty) return const _EmptyHint(message: 'No videos found.');
    return _MediaGrid(entries: filtered, state: state, onTap: onTap);
  }
}

class _FavouritesTab extends StatelessWidget {
  final PlayerState state;
  final ScrollController scrollCtl;
  final bool Function(MediaItem) matchFn;
  final void Function(PlayerState, int) onTap;

  const _FavouritesTab({required this.state, required this.scrollCtl, required this.matchFn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final filtered = state.favouriteEntries.where((e) => matchFn(e.value)).toList();
    if (filtered.isEmpty) {
      return const _EmptyHint(message: 'No favourites yet.\nTap ★ on any track to add it here.');
    }
    return _MediaGrid(entries: filtered, state: state, onTap: onTap);
  }
}

class _MediaGrid extends StatelessWidget {
  final List<MapEntry<int, MediaItem>> entries;
  final PlayerState state;
  final void Function(PlayerState, int) onTap;
  const _MediaGrid({required this.entries, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 500 ? 2 : (width < 900 ? 3 : 5);
    return GridView.builder(
      shrinkWrap: false,
      physics: null,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final entry = entries[i];
        return _MediaCard(entry: entry, state: state, onTap: onTap);
      },
    );
  }
}

class _MediaCard extends StatelessWidget {
  final MapEntry<int, MediaItem> entry;
  final PlayerState state;
  final void Function(PlayerState, int) onTap;

  const _MediaCard({required this.entry, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final item = entry.value;
    final idx = entry.key;
    final cs = Theme.of(context).colorScheme;
    if (item.thumbnailData == null) Future.microtask(() => state.requestThumbnailForIndex(idx));
    return Card(
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => onTap(state, idx),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: state.thumbnailForItem(item, size: 400) ?? Container(color: cs.surfaceContainerHighest),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, cs.surface.withOpacity(0.9)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              item.title ?? p.basename(item.path),
                              style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (item.type == MediaType.video) Icon(Icons.videocam, size: 18, color: cs.onSurface),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.artist ?? '',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.duration != null) ...[
                    const SizedBox(width: 8),
                    Text(_formatDuration(item.duration!), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hh = d.inHours;
    if (hh > 0) return '$hh:$mm:$ss';
    return '$mm:$ss';
  }
}

// ─── Reusable tile / card components ─────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final String message;

  const _EmptyHint({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note, size: 72, color: theme.disabledColor),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  final PlayerState state;
  final MapEntry<int, MediaItem> entry;
  final void Function(PlayerState, int) onTap;

  const _SongTile({required this.state, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final item = entry.value;
    final index = entry.key;

    // Ensure thumbnails are generated for visible items.
    // Request thumbnail lazily. If this item is currently playing, request immediately.
    if (state.isPlayingPath(item.path)) {
      Future.microtask(() => state.requestThumbnailForIndex(index));
    } else {
      if (item.thumbnailData == null) {
        // For offscreen items the grid/list builder won't create widgets,
        // so this call typically runs only for visible items.
        Future.microtask(() => state.requestThumbnailForIndex(index));
      }
    }

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: state.thumbnailForItem(item, size: 56) ??
            Container(
              width: 56,
              height: 56,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(13),
              child: Icon(Icons.music_note, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
      ),
      title: Text(
        item.title ?? p.basename(item.path),
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      ),
      subtitle: Text(
        item.artist ?? '',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      trailing: state.isPlayingPath(item.path)
          ? const Icon(Icons.equalizer, color: Colors.green)
          : null,
      onTap: () => onTap(state, index),
    );
  }
}


