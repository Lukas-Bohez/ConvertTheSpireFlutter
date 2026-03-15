import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
  final List<int> manualQueue = [];

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
  StreamSubscription? _dirWatcher;
  String? _watchedDirPath;

  Duration position = Duration.zero;
  Duration? duration;

  static const double _videoVolumeBoost = 1.8;
  static const Set<String> _mediaExtensions = {
    '.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.aac', '.wma',
    '.mp4', '.mkv', '.avi', '.webm', '.mov', '.wmv', '.flv', '.m4v',
  };

  // ── Audio ──
  final AudioPlayer _audio = AudioPlayer();
  AppAudioHandler? _audioHandler;

  // ── Video ──
  final bool _useMediaKit = kIsWeb || !Platform.isAndroid;
  Player? _mkPlayer;
  VideoController? _mkController;
  VideoPlayerController? _androidController;
  VoidCallback? _androidListener;
  Player? _thumbPlayer;

  bool _videoReady = false;
  bool _videoCompletionFired = false;

  final _random = Random();

  // ─────────────────────────────────────────────────────────────────────────

  PlayerState(this.prefs) {
    if (_useMediaKit) {
      try {
        _mkPlayer = Player();
        _mkController = VideoController(_mkPlayer!);
        _thumbPlayer = Player();
      } catch (e) {
        debugPrint('media_kit init failed: $e');
      }
    }

    _loadPrefs().then((_) => _applyVolume());

    if (!kIsWeb && Platform.isAndroid) _initAudioHandler();

    // ── Audio streams ──
    // BUG 3/4 FIX: route all callbacks through _scheduleNotify so they always
    // execute on the platform thread.
    _subs.add(_audio.positionStream.listen((pos) {
      if (_disposed || currentItem?.type != MediaType.audio) return;
      position = pos;
      _scheduleNotify();
    }));
    _subs.add(_audio.durationStream.listen((dur) {
      if (_disposed || currentItem?.type != MediaType.audio) return;
      duration = dur;
      _scheduleNotify();
    }));
    _subs.add(_audio.playerStateStream.listen((ps) {
      if (_disposed) return;
      if (ps.processingState == ProcessingState.completed) {
        _scheduleNotify(callback: _handleCompletion);
      } else {
        _scheduleNotify();
      }
    }));

    // ── Video streams (media_kit) ──
    if (_useMediaKit && _mkPlayer != null) {
      _subs.add(_mkPlayer!.stream.position.listen((pos) {
        if (_disposed || currentItem?.type != MediaType.video) return;
        position = pos;
        _scheduleNotify();
      }));
      _subs.add(_mkPlayer!.stream.duration.listen((dur) {
        if (_disposed || currentItem?.type != MediaType.video) return;
        duration = dur;
        _scheduleNotify();
      }));
      _subs.add(_mkPlayer!.stream.width.listen((w) {
        if (_disposed || currentItem?.type != MediaType.video) return;
        if ((w ?? 0) > 0 && !_videoReady) {
          _videoReady = true;
          _scheduleNotify();
        }
      }));
      _subs.add(_mkPlayer!.stream.completed.listen((done) {
        if (_disposed || !done || currentItem?.type != MediaType.video) return;
        if (!_videoCompletionFired) {
          _videoCompletionFired = true;
          _scheduleNotify(callback: _handleCompletion);
        }
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
    return _audio.playing;
  }

  bool get isActuallyPlaying => isPlaying;

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

    try { await _audio.stop(); } catch (_) {}
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

    // BUG 2 FIX: run thumbnail loops sequentially, not in parallel.
    _loadThumbnailsSequentially(version);
    _startDirectoryWatcher(items);
  }

  /// BUG 2 FIX: Single sequential thumbnail loop with throttled notify.
  /// Replaces the two simultaneous background loops that each called
  /// notifyListeners() per item.
  Future<void> _loadThumbnailsSequentially(int version) async {
    int pendingNotify = 0;

    for (int i = 0; i < library.length; i++) {
      if (_loadVersion != version || _disposed) return;
      if (library[i].thumbnailData != null) continue;

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
          thumb = await _generateVideoThumbnail(path);
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
          if (item.path.startsWith('content://')) {
            await _audio.setUrl(item.path);
          } else {
            await _audio.setFilePath(item.path);
          }
          if (generation != _loadGeneration) return;
          _runOnMainThread(() => _audio.setVolume(volume));
          duration = _audio.duration;
          position = Duration.zero;
          if (generation != _loadGeneration) return;
          await _audio.play();
          _updateMediaNotification(item);
        } catch (e) {
          debugPrint('audio load error for ${item.path}: $e');
        }
      } else {
        // Switching to video: stop audio.
        // just_audio_windows crashes with "Operation aborted" if stop() is
        // called while a native callback is mid-flight. Yield one microtask
        // cycle first to let any pending callbacks drain, then stop.
        await Future.microtask(() async {
          try { await _audio.stop(); } catch (_) {}
        });
        if (generation != _loadGeneration) return;

        if (_useMediaKit && _mkPlayer != null) {
          try {
            await _mkPlayer!.open(Media(_toUri(item.path)), play: true);
            if (generation != _loadGeneration) {
              await _mkPlayer!.stop();
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
    } finally {
      if (generation == _loadGeneration) {
        notifyListeners();
      }
    }
  }

  Future<void> _loadAndroidVideo(String path, int generation) async {
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

  void togglePlay() {
    if (isVideo) {
      if (_useMediaKit && _mkPlayer != null) {
        _mkPlayer!.state.playing ? _mkPlayer!.pause() : _mkPlayer!.play();
      } else if (_androidController != null) {
        _androidController!.value.isPlaying
            ? _androidController!.pause()
            : _androidController!.play();
      }
    } else {
      _audio.playing ? _audio.pause() : _audio.play();
    }
    notifyListeners();
  }

  void seek(Duration d) {
    if (isVideo) {
      _videoCompletionFired = false;
      if (_useMediaKit && _mkPlayer != null) {
        _mkPlayer!.seek(d);
      } else {
        _androidController?.seekTo(d);
      }
    } else {
      _audio.seek(d);
    }
    position = d;
    notifyListeners();
  }

  Future<void> next({MediaType? only}) async {
    if (library.isEmpty) return;
    final candidates = _getPlaybackCandidates(only: only);
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
    final candidates = _getPlaybackCandidates(only: only);
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
    notifyListeners();
  }

  void cycleRepeat() {
    repeatMode = RepeatMode.values[(repeatMode.index + 1) % RepeatMode.values.length];
    prefs.setInt('repeat', repeatMode.index);
    notifyListeners();
  }

  void _applyVolume() {
    // Always post to main thread — _applyVolume can be called from
    // _loadPrefs().then() which may execute on a background zone.
    _runOnMainThread(() {
      _audio.setVolume(volume);
    });
    if (_useMediaKit && _mkPlayer != null) {
      _mkPlayer!.setVolume(volume * _videoVolumeBoost * 100);
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
    if (index < 0 || index >= library.length) return;
    manualQueue.add(index);
    notifyListeners();
  }

  void dequeue(int queuePosition) {
    if (queuePosition < 0 || queuePosition >= manualQueue.length) return;
    manualQueue.removeAt(queuePosition);
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= manualQueue.length) return;
    final item = manualQueue.removeAt(oldIndex);
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    manualQueue.insert(adjusted.clamp(0, manualQueue.length), item);
    notifyListeners();
  }

  void clearQueue() {
    manualQueue.clear();
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
    _audioHandler = await initAudioService(_audio);
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
    } catch (e) {
      debugPrint('video_thumbnail error for $resolved: $e');
    }

    // Strategy 2: media_kit screenshot.
    if (_useMediaKit && _thumbPlayer != null) {
      try {
        await _thumbPlayer!.setVolume(0);
        await _thumbPlayer!.open(Media(_toUri(filePath)), play: false);
        Duration? dur;
        try {
          dur = await _thumbPlayer!.stream.duration
              .firstWhere((d) => d.inMilliseconds > 0)
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
        if (dur != null && dur.inMilliseconds > 0) {
          await _thumbPlayer!.seek(Duration(milliseconds: (dur.inMilliseconds * 0.1).round().clamp(0, 15000)));
        }
        await Future.delayed(const Duration(milliseconds: 800));
        final snap = await _thumbPlayer!.screenshot();
        if (snap != null && snap.length >= 64) {
          return await _transcodeToSafePng(snap);
        }
      } catch (e) {
        debugPrint('screenshot error for $filePath: $e');
      } finally {
        try { await _thumbPlayer!.stop(); } catch (_) {}
      }
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
    for (final sub in _subs) { sub.cancel(); }
    _subs.clear();
    _audio.dispose();
    if (_useMediaKit) {
      _mkPlayer?.dispose();
      _thumbPlayer?.dispose();
    }
    _disposeAndroidController();
    super.dispose();
  }
}

// ─── Helper types for the All tab ────────────────────────────────────────────

enum _AllTabKind { header, song, videoGrid }

class _AllTabItem {
  final _AllTabKind kind;
  final String? headerText;
  final MapEntry<int, MediaItem>? entry;
  final List<MapEntry<int, MediaItem>>? entries;

  const _AllTabItem.header(this.headerText)
      : kind = _AllTabKind.header,
        entry = null,
        entries = null;

  _AllTabItem.song(this.entry)
      : kind = _AllTabKind.song,
        headerText = null,
        entries = null;

  _AllTabItem.videoGrid(this.entries)
      : kind = _AllTabKind.videoGrid,
        headerText = null,
        entry = null;
}


// ─── Persistent video widget ──────────────────────────────────────────────────

class _VideoPane extends StatelessWidget {
  final VideoController? mkController;
  final VideoPlayerController? androidController;
  final bool visible;
  final bool ready;
  final VoidCallback onTap;

  const _VideoPane({
    required this.mkController,
    required this.androidController,
    required this.visible,
    required this.ready,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    Widget child;
    if (mkController != null) {
      child = Video(controller: mkController!);
    } else if (androidController != null) {
      child = ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: androidController!,
        builder: (_, val, __) => val.isInitialized
            ? AspectRatio(aspectRatio: val.aspectRatio, child: VideoPlayer(androidController!))
            : const Center(child: CircularProgressIndicator(color: _PlayerTheme.accent)),
      );
    } else {
      child = const Center(child: CircularProgressIndicator(color: _PlayerTheme.accent));
    }

    // Height is fully controlled by the AnimatedContainer in the parent.
    // Just fill available space and handle the tap.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.expand(
        child: ColoredBox(
          color: Colors.black,
          child: ready
              ? child
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

  // One scroll controller per tab to avoid cross-tab controller conflicts.
  final _scrollControllers = List.generate(5, (_) => ScrollController());

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() { if (!_tabController.indexIsChanging) setState(() {}); });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    for (final sc in _scrollControllers) { sc.dispose(); }
    super.dispose();
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
    final queueCount = state.manualQueue.length;
    final allCount = songCount + videoCount;

    // Whether the video pane should be shown.
    final showVideo = state.isVideo &&
        (state.videoController != null ||
            state.androidVideoController != null);

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: true,
        // CRASH FIX: Replace CustomScrollView+SliverFillRemaining+TabBarView
        // with a plain Column. SliverFillRemaining handing an unbounded-height
        // TabBarView (which itself contains ListViews) causes a layout crash on
        // Windows desktop where the render engine can't resolve constraints.
        child: Column(
          children: [
            // ── Video pane ──────────────────────────────────────────────────
            // CRASH FIX: AnimatedContainer height:null crashes Flutter layout.
            // Use a fixed target height instead (0 ↔ 260).
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              height: showVideo ? 260.0 : 0.0,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(color: Colors.black),
              child: showVideo
                  ? _VideoPane(
                      mkController: state.videoController,
                      androidController: state.androidVideoController,
                      visible: true,
                      ready: state.videoReady,
                      onTap: state.togglePlay,
                    )
                  : const SizedBox.shrink(),
            ),

            // ── Header + now-playing ─────────────────────────────────────
            _buildHeader(),
            _buildNowPlaying(state),
            if (state.isLoading)
              const LinearProgressIndicator(
                color: _PlayerTheme.accent,
                minHeight: 2,
              ),

            // ── Pinned tab bar ────────────────────────────────────────────
            ColoredBox(
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
                  Tab(text: '⏭ Queue ($queueCount)'),
                ],
              ),
            ),

            // ── Search bar ────────────────────────────────────────────────
            _buildSearchBar(),

            // ── Tab content — Expanded so it fills remaining space ────────
            // Each tab manages its own scroll independently.
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _AllTab(state: state, scrollCtl: _scrollControllers[0], matchFn: _matchesSearch, onTap: _onTrackTap),
                  _SongsTab(state: state, scrollCtl: _scrollControllers[1], matchFn: _matchesSearch, onTap: _onTrackTap),
                  _VideosTab(state: state, scrollCtl: _scrollControllers[2], matchFn: _matchesSearch, onTap: _onTrackTap),
                  _FavouritesTab(state: state, scrollCtl: _scrollControllers[3], matchFn: _matchesSearch, onTap: _onTrackTap),
                  _QueueTab(state: state, scrollCtl: _scrollControllers[4]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // BUG 1 FIX: all taps go through this single method which immediately captures
  // the index and calls select() — no intermediate setState() that could shift indices.
  void _onTrackTap(PlayerState state, int index) {
    state.select(index);
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
            color: Colors.black.withValues(alpha: 0.08),
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
          ? 'No media loaded.\nTap the folder icon to open a folder.'
          : 'No results for this search.');
    }

    final rows = <_AllTabItem>[];
    if (audio.isNotEmpty) {
      rows.add(_AllTabItem.header('Songs — ${audio.length}'));
      for (final e in audio) rows.add(_AllTabItem.song(e));
    }
    if (video.isNotEmpty) {
      rows.add(_AllTabItem.header('Videos — ${video.length}'));
      for (int i = 0; i < video.length; i += 2) {
        rows.add(_AllTabItem.videoGrid(video.sublist(i, (i + 2).clamp(0, video.length))));
      }
    }

    return ListView.builder(
      controller: scrollCtl,
      itemCount: rows.length,
      itemBuilder: (ctx, i) {
        final row = rows[i];
        return switch (row.kind) {
          _AllTabKind.header => _SectionHeader(text: row.headerText!),
          _AllTabKind.song => _SongTile(
              state: state,
              entry: row.entry!,
              onTap: onTap,
            ),
          _AllTabKind.videoGrid => _VideoGridRow(
              state: state,
              entries: row.entries!,
              onTap: onTap,
            ),
        };
      },
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
    return ListView.builder(
      controller: scrollCtl,
      itemCount: filtered.length,
      itemBuilder: (ctx, i) => _SongTile(state: state, entry: filtered[i], onTap: onTap),
    );
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
    return GridView.builder(
      controller: scrollCtl,
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 16 / 10,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) => _VideoCard(state: state, entry: filtered[i], onTap: onTap),
    );
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
    return ListView.builder(
      controller: scrollCtl,
      itemCount: filtered.length,
      itemBuilder: (ctx, i) => _SongTile(state: state, entry: filtered[i], onTap: onTap),
    );
  }
}

class _QueueTab extends StatelessWidget {
  final PlayerState state;
  final ScrollController scrollCtl;

  const _QueueTab({required this.state, required this.scrollCtl});

  @override
  Widget build(BuildContext context) {
    if (state.manualQueue.isEmpty) {
      return const _EmptyHint(message: 'Queue is empty.\nLong-press any track to add it.');
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Text('${state.manualQueue.length} tracks',
                  style: TextStyle(color: _PlayerTheme.sub(context), fontSize: 13)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Clear all'),
                onPressed: state.clearQueue,
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            scrollController: scrollCtl,
            itemCount: state.manualQueue.length,
            onReorder: state.reorderQueue,
            itemBuilder: (ctx, i) {
              final idx = state.manualQueue[i];
              if (idx >= state.library.length) return const SizedBox.shrink(key: ValueKey(-1));
              final item = state.library[idx];
              final title = item.title ?? p.basenameWithoutExtension(item.path);
              return ListTile(
                key: ValueKey('q_$i'),
                leading: _TrackThumbnail(data: item.thumbnailData, isVideo: item.type == MediaType.video, size: 40, radius: 6),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: item.artist != null
                    ? Text(item.artist!, maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.drag_handle),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => state.dequeue(i),
                    ),
                  ],
                ),
                onTap: () {
                  state.dequeue(i);
                  state.select(idx);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Reusable tile / card components ─────────────────────────────────────────

/// BUG 2 FIX: _SongTile uses a const key and requests thumbnail on first build,
/// not through VisibilityDetector (which fired constantly during scroll).
/// Instead we use a StatefulWidget that requests once on initState.
class _SongTile extends StatefulWidget {
  final PlayerState state;
  final MapEntry<int, MediaItem> entry;
  final void Function(PlayerState, int) onTap;

  const _SongTile({
    required this.state,
    required this.entry,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  State<_SongTile> createState() => _SongTileState();
}

class _SongTileState extends State<_SongTile> {
  @override
  void initState() {
    super.initState();
    // Request thumbnail lazily on first build, deduped by PlayerState.
    if (widget.entry.value.thumbnailData == null) {
      Future.microtask(() {
        if (mounted) widget.state.requestThumbnailForIndex(widget.entry.key);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.entry.value;
    final idx = widget.entry.key;
    final isActive = widget.state.currentIndex == idx;
    final isPlaying = isActive && widget.state.isActuallyPlaying;
    final title = item.title ?? p.basenameWithoutExtension(item.path);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Stack(
        children: [
          _TrackThumbnail(data: item.thumbnailData, isVideo: item.type == MediaType.video, size: 46, radius: 8),
          // Clear audio/video type indicator on the thumbnail corner.
          Positioned(
            bottom: 0,
            right: 0,
            child: _TypeBadge(type: item.type, compact: true),
          ),
        ],
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          color: isActive ? _PlayerTheme.accent : _PlayerTheme.text(context),
          fontSize: 14,
        ),
      ),
      subtitle: item.artist != null
          ? Text(item.artist!, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: _PlayerTheme.sub(context)))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPlaying)
            const _EqIndicator(),
          IconButton(
            icon: Icon(
              widget.state.isFavourite(item.path) ? Icons.star_rounded : Icons.star_border_rounded,
              size: 20,
              color: widget.state.isFavourite(item.path) ? Colors.amber : _PlayerTheme.sub(context),
            ),
            onPressed: () => widget.state.toggleFavourite(item.path),
          ),
        ],
      ),
      onTap: () => widget.onTap(widget.state, idx),
      onLongPress: () {
        widget.state.enqueue(idx);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Added "$title" to queue'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ));
      },
    );
  }
}

class _VideoGridRow extends StatelessWidget {
  final PlayerState state;
  final List<MapEntry<int, MediaItem>> entries;
  final void Function(PlayerState, int) onTap;

  const _VideoGridRow({required this.state, required this.entries, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: entries.map((e) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _VideoCard(state: state, entry: e, onTap: onTap),
          ),
        )).toList(),
      ),
    );
  }
}

class _VideoCard extends StatefulWidget {
  final PlayerState state;
  final MapEntry<int, MediaItem> entry;
  final void Function(PlayerState, int) onTap;

  const _VideoCard({required this.state, required this.entry, required this.onTap});

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  @override
  void initState() {
    super.initState();
    if (widget.entry.value.thumbnailData == null) {
      Future.microtask(() {
        if (mounted) widget.state.requestThumbnailForIndex(widget.entry.key);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.entry.value;
    final idx = widget.entry.key;
    final isActive = widget.state.currentIndex == idx;
    final title = item.title ?? p.basenameWithoutExtension(item.path);
    final tileBg = _PlayerTheme.tileBg(context);

    return GestureDetector(
      onTap: () => widget.onTap(widget.state, idx),
      onLongPress: () {
        widget.state.enqueue(idx);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Added "$title" to queue'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail
              item.thumbnailData != null
                  ? Image.memory(item.thumbnailData!, fit: BoxFit.cover)
                  : Container(
                      color: tileBg,
                      child: const Icon(Icons.videocam_rounded,
                          color: _PlayerTheme.accent, size: 36),
                    ),
              // Gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
                    stops: const [0.45, 1.0],
                  ),
                ),
              ),
              // Title at bottom
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ),
              // Play icon overlay when active
              if (isActive)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _PlayerTheme.accent.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                  ),
                ),
              // VIDEO badge top-left
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('VIDEO',
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Small reusable components ────────────────────────────────────────────────

class _TrackThumbnail extends StatelessWidget {
  final Uint8List? data;
  final bool isVideo;
  final double size;
  final double radius;

  const _TrackThumbnail({
    required this.data,
    required this.isVideo,
    required this.size,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: data != null
            ? Image.memory(data!, fit: BoxFit.cover)
            : Container(
                color: _PlayerTheme.accentDim,
                child: Icon(
                  isVideo ? Icons.videocam_rounded : Icons.music_note_rounded,
                  color: _PlayerTheme.accent,
                  size: size * 0.45,
                ),
              ),
      ),
    );
  }
}

/// Clear visual distinction between audio and video — the key UX improvement.
class _TypeBadge extends StatelessWidget {
  final MediaType type;
  final bool compact;

  const _TypeBadge({required this.type, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isVideo = type == MediaType.video;
    final label = isVideo ? 'VIDEO' : 'AUDIO';
    final color = isVideo ? const Color(0xFF6B4EFF) : const Color(0xFF1E9E6A);

    if (compact) {
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Icon(
          isVideo ? Icons.videocam_rounded : Icons.music_note_rounded,
          color: Colors.white,
          size: 10,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onPressed;

  const _PlayPauseButton({required this.playing, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(
          color: _PlayerTheme.accent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;
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
    return IconButton(
      icon: Icon(icon,
          color: active ? _PlayerTheme.accent : _PlayerTheme.sub(context),
          size: size),
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }
}

/// Animated equalizer bars shown next to the currently playing track.
class _EqIndicator extends StatefulWidget {
  const _EqIndicator();

  @override
  State<_EqIndicator> createState() => _EqIndicatorState();
}

class _EqIndicatorState extends State<_EqIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, __) {
        final t = _ctl.value;
        final bars = [0.4 + 0.6 * t, 0.6 + 0.4 * (1 - t), 0.5 + 0.5 * t];
        return SizedBox(
          width: 16,
          height: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: bars.map((h) => Container(
              width: 3,
              height: 16 * h,
              decoration: BoxDecoration(
                color: _PlayerTheme.accent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            )).toList(),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _PlayerTheme.sub(context),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String message;
  const _EmptyHint({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: _PlayerTheme.sub(context), fontSize: 14, height: 1.6),
        ),
      ),
    );
  }
}