// ignore_for_file: unused_element, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException, DeviceOrientation, SystemChrome, SystemUiMode, KeyDownEvent, LogicalKeyboardKey;
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
import 'package:window_manager/window_manager.dart';
import '../services/platform_dirs.dart';
import '../services/audio_handler.dart';
import '../services/background_media_update_guard.dart';
import '../services/ffmpeg_service.dart';
import '../utils/snack.dart';
import '../utils/lock.dart';
import '../vault/platform/desktop_window.dart';

// --- Public entry point -------------------------------------------------------

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) => const PlayerScreen();
}

// --- Enums & data types -------------------------------------------------------

enum MediaType { audio, video }

enum RepeatMode { off, one, all }

enum PlaybackMode { all, songs, videos, favourites, favouriteSongs, favouriteVideos }

enum QueueScope { all, songs, videos, favourites, favSongs, favVideos }

enum MediaSortOrder { newestFirst, oldestFirst, titleAZ, titleZA, shortestDuration }

class MediaItem {
  final String path;
  final MediaType type;
  final String? title;
  final String? artist;
  final String? genre;
  final DateTime? modifiedAt;
  final Uint8List? thumbnailData;
  final Duration? duration;

  const MediaItem(
    this.path,
    this.type, {
    this.title,
    this.artist,
    this.genre,
    this.modifiedAt,
    this.thumbnailData,
    this.duration,
  });

  MediaItem copyWith({
    String? title,
    String? artist,
    String? genre,
    DateTime? modifiedAt,
    Uint8List? thumbnailData,
    Duration? duration,
  }) =>
      MediaItem(
        path,
        type,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        genre: genre ?? this.genre,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        thumbnailData: thumbnailData ?? this.thumbnailData,
        duration: duration ?? this.duration,
      );
}

class PositionUiState {
  final Duration position;
  final Duration duration;
  final bool isSeeking;

  const PositionUiState({
    required this.position,
    required this.duration,
    required this.isSeeking,
  });
}

// --- Thumbnail helpers (unchanged - they work fine) --------------------------

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

// --- PlayerState --------------------------------------------------------------
//
// FIX SUMMARY:
//
// BUG 1 - Wrong track on tap:
//   Root cause: select(idx) set currentIndex then called _loadCurrent(). But
//   _loadingTrack guard dropped subsequent calls while setting _pendingReload=true.
//   When pending reload fired, currentIndex had been mutated by later taps.
//   FIX: _loadCurrent now receives the target index as a parameter and captures
//   it immediately. The guard uses a serial "generation" counter; stale loads
//   self-cancel without corrupting currentIndex.
//
// BUG 2 - Thumbnail storm / slow scrolling:
//   Root cause: Both background loops + per-item VisibilityDetector all called
//   notifyListeners() independently, causing O(n) full rebuilds simultaneously.
//   FIX: Background thumbnail loading is serialised through a single
//   throttled notify (at most once per 150 ms). VisibilityDetector requests are
//   deduplicated with a pending-set so each index is only processed once.
//
// BUG 3 - Video crash (Lost connection to device):
//   Root cause: media_kit stream listeners (position, completed, etc.) fire on
//   background threads and called notifyListeners() directly - illegal on Flutter.
//   FIX: All stream callbacks are routed through a microtask-queued dispatcher
//   (_scheduleNotify) that coalesces rapid updates and always executes on the
//   platform thread via scheduleMicrotask / WidgetsBinding.instance.
//
// BUG 4 - just_audio_windows threading error:
//   Root cause: setVolume called on non-platform thread from stream listeners.
//   FIX: All just_audio calls are wrapped in _runOnMainThread().

class PlayerState with ChangeNotifier {
  // TECH-DEBT: add first-class sleep timer state/countdown exposure for all
  // player surfaces (main player + mini overlay) in a dedicated follow-up.
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
  final List<int> _playHistory = [];
  int _historyCursor = -1;
  final List<int> _recentlyPlayed = [];
  static const int _maxHistoryEntries = 50;
  static const int _maxRecentShuffleEntries = 24;

  Directory? _thumbCacheDir;
  Set<String> _favourites = {};
  Set<String> _disliked = {};
  Map<String, MediaItem> _favouriteCache = {};
  int _folderItemCount = 0;

  // BUG 1 FIX: generation counter - each _loadCurrent call captures generation
  // at start; if generation changes mid-load the load aborts.
  int _loadGeneration = 0;

  // BUG 2 FIX: version counter for library loads - background loops abort when
  // this changes.
  int _loadVersion = 0;

  // BUG 2 FIX: serialised notify - coalesce multiple rapid state changes.
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
  bool _libraryRefreshInProgress = false;
  bool _libraryRefreshQueued = false;

  Duration position = Duration.zero;
  Duration? duration;
  DateTime? _lastMkOpenTime;
  final StreamController<PositionUiState> _positionUiController =
      StreamController<PositionUiState>.broadcast();
  bool _isSeeking = false;
  Duration? _seekPreviewPosition;
  Duration? _pendingSeekTarget;
  Timer? _seekDebounceTimer;

  static const double _videoVolumeBoost = 1.8;
  static const Set<String> _mediaExtensions = {
    '.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.aac', '.wma',
    '.mp4', '.mkv', '.avi', '.webm', '.mov', '.wmv', '.flv', '.m4v',
  };

  // -- Audio --
  AudioPlayer? _audio;
  AppAudioHandler? _audioHandler;
  MediaItem? _pendingNotificationItem;
  final BackgroundMediaUpdateGuard _notificationGuard =
      BackgroundMediaUpdateGuard();

  // 1x1 transparent PNG to force Android media notifications to replace
  // stale artwork when the current item has no thumbnail yet.
  static final Uint8List _transparentArtPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO8QXWQAAAAASUVORK5CYII=',
  );

  // -- Video --
  // Keep Windows on media_kit for playback. Windows remains excluded from
  // thumbnail screenshot generation elsewhere to avoid native instability.
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
  bool _videoBackgroundAudioMode = false;
  bool _desktopVideoBackgroundAudioMode = false;
  Duration? _backgroundVideoResumePosition;
  final Set<String> _ignoredBrokenMediaPaths = <String>{};

  // Protects concurrent thumbnail generation / screenshot operations.
  final _thumbLock = Lock();
  DateTime? _lastThumbOpenTime;

  // video suspension for resize removed - avoid interfering with media_kit

  final _random = Random();
  final _audioLock = Lock();

  // -------------------------------------------------------------------------

  PlayerState(this.prefs) {
    if (_useMediaKit) {
      _initMkPlayers();
    }

    if (!kIsWeb && Platform.isAndroid) {
      _audio ??= AudioPlayer();
    }

    _loadPrefs().then((_) => _applyVolume());

    if (!_useMediaKit && !kIsWeb && Platform.isAndroid) _initAudioHandler();

    // -- Audio streams --
    // BUG 3/4 FIX: route all callbacks through _scheduleNotify so they always
    // execute on the platform thread. Only create the just_audio player on Android
    // where media_kit is not used.
    if (!kIsWeb && Platform.isAndroid) {
      _audio ??= AudioPlayer();
      _subs.add(_audio!.positionStream.listen((pos) {
        if (_disposed || currentItem?.type != MediaType.audio) return;
        _onPlaybackPositionUpdated(pos);
      }));
      _subs.add(_audio!.durationStream.listen((dur) {
        if (_disposed || currentItem?.type != MediaType.audio) return;
        duration = dur;
        _emitPositionUiState();
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
        if (!Platform.isWindows) {
          _thumbPlayer ??= Player();
        }
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
    if (!_useMediaKit || Platform.isWindows) {
      return;
    }
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
      _onPlaybackPositionUpdated(pos);
    }));
    _mkSubs.add(player.stream.duration.listen((dur) {
      if (_disposed) return;
      if (isAudio) {
        if (currentItem?.type != MediaType.audio) return;
      } else {
        if (currentItem?.type != MediaType.video) return;
      }
      duration = dur;
      _emitPositionUiState();
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
    // CRITICAL: do NOT call callback synchronously here - the caller is on a
    // background thread. Queue it alongside the notify.
    if (_notifyPending && callback == null) return;
    if (!_notifyPending) _notifyPending = true;
    Future.microtask(() {
      if (_disposed) return;
      _notifyPending = false;
      callback?.call();   // now on main isolate - safe to call plugin methods
      notifyListeners();
    });
  }

  // --- Getters --------------------------------------------------------------

  MediaItem? get currentItem {
    if (library.isEmpty) return null;
    if (currentIndex < 0 || currentIndex >= library.length) currentIndex = 0;
    return library[currentIndex];
  }

  bool get isVideo => currentItem?.type == MediaType.video;
  bool get videoReady => _videoReady;
  Stream<PositionUiState> get positionUiStream => _positionUiController.stream;
  Duration get bufferedPosition {
    if (_audio != null) {
      return _audio!.bufferedPosition;
    }
    final android = _androidController;
    if (android != null && android.value.isInitialized) {
      final ranges = android.value.buffered;
      if (ranges.isNotEmpty) {
        return ranges.last.end;
      }
    }
    return position;
  }

  bool get isPlaying {
    if (isVideo) {
      if (_videoBackgroundAudioMode && _audio != null) {
        return _audio!.playing;
      }
      if (_desktopVideoBackgroundAudioMode && _audioMkPlayer != null) {
        return _audioMkPlayer!.state.playing;
      }
      if (_useMediaKit && _mkPlayer != null) return _mkPlayer!.state.playing;
      return _androidController?.value.isPlaying ?? false;
    }
    if (_audio != null) {
      return _audio!.playing;
    }
    if (_useMediaKit) {
      return _audioMkPlayer?.state.playing ?? false;
    }
    return _audio?.playing ?? false;
  }

  bool get isActuallyPlaying => isPlaying;

  void _emitPositionUiState() {
    if (_positionUiController.isClosed) return;
    _positionUiController.add(
      PositionUiState(
        position: _isSeeking ? (_seekPreviewPosition ?? position) : position,
        duration: duration ?? Duration.zero,
        isSeeking: _isSeeking,
      ),
    );
  }

  void _onPlaybackPositionUpdated(Duration pos) {
    position = pos;
    if (_isSeeking) {
      final pending = _pendingSeekTarget ?? _seekPreviewPosition;
      if (pending == null || (pos - pending).inMilliseconds.abs() <= 350) {
        _isSeeking = false;
        _seekPreviewPosition = null;
        _pendingSeekTarget = null;
      }
    }
    _emitPositionUiState();
  }

  int mediaIndexForPath(String path) => library.indexWhere((item) => item.path == path);

  bool isPlayingPath(String path) => currentItem?.path == path && isActuallyPlaying;

  Widget? thumbnailForItem(MediaItem item, {required int size, bool expand = false}) {
    final data = item.thumbnailData;
    if (data == null) return null;
    if (expand) {
      return Image.memory(data, fit: BoxFit.cover);
    }
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
    List<int> get queueSnapshot => List<int>.unmodifiable(
      manualQueue.where((index) => index >= 0 && index < library.length));
    List<int> get playHistorySnapshot => List<int>.unmodifiable(
      _playHistory.where((index) => index >= 0 && index < library.length));

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
  bool isDisliked(String path) => _disliked.contains(path);

  // --- Favourites -----------------------------------------------------------

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

  void toggleDislike(String path) {
    if (_disliked.contains(path)) {
      _disliked.remove(path);
    } else {
      _disliked.add(path);
    }
    prefs.setStringList('player_disliked', _disliked.toList());
    notifyListeners();
  }

  Future<bool> deleteMediaItem(String path) async {
    final index = library.indexWhere((item) => item.path == path);
    if (index < 0) return false;
    if (path.startsWith('content://')) {
      debugPrint('deleteMediaItem: content URI deletion is not supported: $path');
      return false;
    }

    final file = File(path);
    try {
      if (!await file.exists()) return false;
      await file.delete();
    } catch (e) {
      debugPrint('deleteMediaItem failed for $path: $e');
      return false;
    }

    final wasCurrent = index == currentIndex;
    _favourites.remove(path);
    _favouriteCache.remove(path);
    _disliked.remove(path);
    prefs.setStringList('player_favourites', _favourites.toList());
    prefs.setStringList('player_disliked', _disliked.toList());
    _saveFavouriteCache();

    library.removeAt(index);
    _rebaseStateAfterRemoval(index);

    if (library.isEmpty) {
      await _stopPlaybackBestEffort();
      currentIndex = 0;
      position = Duration.zero;
      duration = null;
      _folderItemCount = 0;
      notifyListeners();
      return true;
    }

    if (wasCurrent) {
      currentIndex = index.clamp(0, library.length - 1);
      await select(currentIndex);
    } else {
      notifyListeners();
    }
    return true;
  }

  void _rebaseStateAfterRemoval(int removedIndex) {
    manualQueue.removeWhere((value) => value == removedIndex);
    _manualQueueBase.removeWhere((value) => value == removedIndex);

    for (var i = 0; i < manualQueue.length; i++) {
      if (manualQueue[i] > removedIndex) manualQueue[i]--;
    }
    for (var i = 0; i < _manualQueueBase.length; i++) {
      if (_manualQueueBase[i] > removedIndex) _manualQueueBase[i]--;
    }

    if (currentIndex > removedIndex) {
      currentIndex--;
    }

    if (_folderItemCount > removedIndex) {
      _folderItemCount--;
    } else {
      _folderItemCount = min(_folderItemCount, library.length);
    }

    for (var i = _playHistory.length - 1; i >= 0; i--) {
      final value = _playHistory[i];
      if (value == removedIndex) {
        _playHistory.removeAt(i);
      } else if (value > removedIndex) {
        _playHistory[i] = value - 1;
      }
    }
    for (var i = _recentlyPlayed.length - 1; i >= 0; i--) {
      final value = _recentlyPlayed[i];
      if (value == removedIndex) {
        _recentlyPlayed.removeAt(i);
      } else if (value > removedIndex) {
        _recentlyPlayed[i] = value - 1;
      }
    }
    if (_playHistory.isEmpty) {
      _historyCursor = -1;
    } else {
      _historyCursor = _historyCursor.clamp(0, _playHistory.length - 1);
    }
  }

  Future<void> _stopPlaybackBestEffort() async {
    _loadGeneration++;
    _videoCompletionFired = false;
    _videoReady = false;
    try { await _safeStopAudio(); } catch (_) {}
    try { await _audioMkPlayer?.stop(); } catch (_) {}
    try { await _mkPlayer?.stop(); } catch (_) {}
    try { await _disposeAndroidController(); } catch (_) {}
  }

  Future<void> _safeStopAudio() async {
    if (_audio == null) return;
    if (!kIsWeb && Platform.isWindows) {
      try { await _audio!.pause(); } catch (_) {}
      try { await _audio!.seek(Duration.zero); } catch (_) {}
      return;
    }
    try { await _audio!.stop(); } catch (_) {}
  }

  void _saveFavouriteCache() {
    final list = <String>[];
    for (final path in _favourites) {
      final item = _favouriteCache[path];
      if (item != null) {
        list.add('${item.path}\t${item.type == MediaType.video ? 'v' : 'a'}'
            '\t${item.title ?? ''}\t${item.artist ?? ''}\t${item.genre ?? ''}'
            '\t${item.modifiedAt?.toIso8601String() ?? ''}');
        if (item.thumbnailData != null) _saveThumbToCache(path, item.thumbnailData!);
      }
    }
    prefs.setStringList('player_favourites_cache', list);
  }

  // --- Thumb disk cache -----------------------------------------------------

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

  // --- Library loading ------------------------------------------------------

  Future<void> setLibrary(List<MediaItem> items) async {
    final version = ++_loadVersion;
    isLoading = true;
    _folderItemCount = 0;
    _thumbInFlight.clear();
    _playHistory.clear();
    _recentlyPlayed.clear();
    _historyCursor = -1;

    if (_audio != null) {
      try { await _safeStopAudio(); } catch (_) {}
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
    if (library.isNotEmpty) {
      _recordHistorySelection(currentIndex, fromHistory: false);
    }
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
          // BUG 2 FIX: batch notifies - only fire every 5 items or end of list,
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
          if (index == currentIndex) {
            _updateMediaNotification(library[index]);
          }
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
        genre: _extractGenre(tag) ?? item.genre,
        modifiedAt: item.modifiedAt ?? _modifiedAtForPath(item.path),
      );
      if (i == currentIndex) {
        _updateMediaNotification(lib[i]);
      }
    } catch (_) {}
  }

  // --- Playback selection ---------------------------------------------------

  /// BUG 1 FIX: select() captures the target index into a local variable and
  /// passes it directly to _loadCurrent(). The generation counter ensures that
  /// if select() is called again before _loadCurrent() finishes, the earlier
  /// load aborts gracefully instead of landing on the wrong track.
  Future<void> select(int index) async {
    await _selectInternal(index, fromHistory: false);
  }

  Future<void> _selectInternal(int index, {required bool fromHistory}) async {
    if (index < 0 || index >= library.length) return;
    _recordHistorySelection(index, fromHistory: fromHistory);
    // Capture NOW before any async gap.
    final targetIndex = index;
    final generation = ++_loadGeneration;
    currentIndex = targetIndex;
    notifyListeners();
    await _loadCurrent(targetIndex, generation);
  }

  void _recordHistorySelection(int index, {required bool fromHistory}) {
    if (!fromHistory) {
      if (_historyCursor < _playHistory.length - 1) {
        _playHistory.removeRange(_historyCursor + 1, _playHistory.length);
      }
      if (_playHistory.isEmpty || _playHistory.last != index) {
        _playHistory.add(index);
        if (_playHistory.length > _maxHistoryEntries) {
          _playHistory.removeAt(0);
        }
      }
      _historyCursor = _playHistory.length - 1;
      _pushRecentPlay(index);
      return;
    }

    final existing = _playHistory.lastIndexOf(index);
    if (existing >= 0) {
      _historyCursor = existing;
    }
  }

  void _pushRecentPlay(int index) {
    _recentlyPlayed.remove(index);
    _recentlyPlayed.add(index);
    while (_recentlyPlayed.length > _maxRecentShuffleEntries) {
      _recentlyPlayed.removeAt(0);
    }
  }

  Future<void> _loadCurrent(int targetIndex, int generation) async {
    if (_disposed) return;
    if (targetIndex < 0 || targetIndex >= library.length) return;

    // Reset any in-flight slider interaction when switching tracks to avoid
    // stale debounce seeks leaking into the newly selected item.
    _resetSeekInteractionState();

    // BUG 1 FIX: abort if a newer select() has been called.
    if (generation != _loadGeneration) {
      debugPrint('_loadCurrent: stale generation $generation (current: $_loadGeneration), aborting');
      return;
    }

    // Snapshot the item at load time - don't rely on currentItem getter.
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
                  debugPrint('Skipping rapid audio open - too soon');
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
                await _handleMalformedMedia(item.path, e, context: 'media_kit audio load');
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
          await _handleMalformedMedia(item.path, e, context: 'audio load');
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
              debugPrint('Skipping rapid mk open - too soon');
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
            await _handleMalformedMedia(item.path, e, context: 'media_kit video load');
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
    _emitPositionUiState();
    await ctrl.setVolume((volume * _videoVolumeBoost).clamp(0.0, 1.0));
    await ctrl.play();
    _videoReady = true;

    void listener() {
      if (_androidController == null) return;
      final val = _androidController!.value;
      if (currentItem?.type == MediaType.video) {
        _onPlaybackPositionUpdated(val.position);
        if (val.duration != Duration.zero) {
          duration = val.duration;
          _emitPositionUiState();
        }
      }
      if (!_videoCompletionFired &&
          val.duration != Duration.zero &&
          val.position >= val.duration &&
          !val.isPlaying) {
        _videoCompletionFired = true;
        _handleCompletion();
        _scheduleNotify();
      }
    }

    _androidListener = listener;
    ctrl.addListener(listener);
  } catch (e, st) {
    debugPrint('Android video player failed: $e\n$st');
    await _handleMalformedMedia(path, e, context: 'android video load');
  }
}

  Future<void> onAppLifecycleChanged(AppLifecycleState state) async {
    if (_disposed) return;

    if (Platform.isAndroid) {
      if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused) {
        await _enterBackgroundVideoAudioMode();
        return;
      }
      if (state == AppLifecycleState.resumed) {
        await _restoreForegroundVideoPlayback();
      }
      return;
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused) {
        await _enterDesktopBackgroundVideoAudioMode();
        return;
      }
      if (state == AppLifecycleState.resumed) {
        await _restoreDesktopForegroundVideoPlayback();
      }
    }
  }

  Future<void> _enterDesktopBackgroundVideoAudioMode() async {
    if (_desktopVideoBackgroundAudioMode || _disposed) return;
    if (!_useMediaKit || _mkPlayer == null || _audioMkPlayer == null) return;

    final item = currentItem;
    if (item == null || item.type != MediaType.video) return;

    final resumePosition = position;
    final wasPlaying = _mkPlayer!.state.playing;
    _backgroundVideoResumePosition = resumePosition;

    try {
      await _mkPlayer!.pause();
    } catch (_) {}

    await _audioLock.acquire();
    try {
      await _openMediaWithFallback(_audioMkPlayer!, item.path, play: false);
      if (resumePosition > Duration.zero) {
        try {
          await _audioMkPlayer!.seek(resumePosition);
        } catch (_) {}
      }
      await _audioMkPlayer!.setVolume(volume * _videoVolumeBoost * 100);
      if (wasPlaying) {
        await _audioMkPlayer!.play();
      } else {
        await _audioMkPlayer!.pause();
      }
      _desktopVideoBackgroundAudioMode = true;
      _updateMediaNotification(item);
      _emitPositionUiState();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to enter desktop background video audio mode: $e');
      _desktopVideoBackgroundAudioMode = false;
    } finally {
      _audioLock.release();
    }
  }

  Future<void> _restoreDesktopForegroundVideoPlayback() async {
    if (!_desktopVideoBackgroundAudioMode || _disposed) return;
    final item = currentItem;
    if (item == null || item.type != MediaType.video || _mkPlayer == null) {
      _desktopVideoBackgroundAudioMode = false;
      notifyListeners();
      return;
    }

    final resumePosition = _backgroundVideoResumePosition ?? position;
    final shouldKeepPlaying = _audioMkPlayer?.state.playing ?? false;

    try {
      await _audioMkPlayer?.pause();
    } catch (_) {}

    try {
      await _openMediaWithFallback(_mkPlayer!, item.path, play: false);
      if (resumePosition > Duration.zero) {
        try {
          await _mkPlayer!.seek(resumePosition);
        } catch (_) {}
      }
      await _mkPlayer!.setVolume(volume * _videoVolumeBoost * 100);
      if (shouldKeepPlaying) {
        await _mkPlayer!.play();
      } else {
        await _mkPlayer!.pause();
      }
      position = resumePosition;
      _videoReady = true;
      _emitPositionUiState();
    } catch (e) {
      debugPrint('Failed to restore desktop foreground video playback: $e');
    }

    _desktopVideoBackgroundAudioMode = false;
    notifyListeners();
  }

  Future<void> _enterBackgroundVideoAudioMode() async {
    if (_videoBackgroundAudioMode || _disposed) return;
    if (_useMediaKit || _audio == null) return;

    final item = currentItem;
    if (item == null || item.type != MediaType.video) return;
    final controller = _androidController;
    if (controller == null) return;

    final resumePosition = controller.value.position;
    final wasPlaying = controller.value.isPlaying;
    _backgroundVideoResumePosition = resumePosition;

    try {
      await controller.pause();
      await controller.setVolume(0);
    } catch (_) {}

    try {
      final localPath = await _resolveLocalPath(item.path);
      if (localPath.startsWith('http') || localPath.startsWith('content://')) {
        await _audio!.setUrl(localPath);
      } else {
        await _audio!.setFilePath(localPath);
      }
      if (resumePosition > Duration.zero) {
        await _audio!.seek(resumePosition);
      }
      _runOnMainThread(() => _audio!.setVolume(volume));
      if (wasPlaying) {
        await _audio!.play();
      } else {
        await _audio!.pause();
      }
      duration = _audio!.duration ?? duration;
      position = resumePosition;
      _videoBackgroundAudioMode = true;
      _updateMediaNotification(item);
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to enter background video audio mode: $e');
      _videoBackgroundAudioMode = false;
    }
  }

  Future<void> _restoreForegroundVideoPlayback() async {
    if (!_videoBackgroundAudioMode || _disposed) return;
    final item = currentItem;
    final resumePosition = _backgroundVideoResumePosition ?? position;
    final shouldKeepPlaying = _audio?.playing ?? false;

    try {
      await _audio?.pause();
    } catch (_) {}

    _videoBackgroundAudioMode = false;

    if (item == null || item.type != MediaType.video) {
      notifyListeners();
      return;
    }

    // Reuse current Android controller when available to avoid a full reload
    // that can leave timeline/progress in a stale visual state.
    final existingController = _androidController;
    if (!_useMediaKit && existingController != null) {
      try {
        await existingController.setVolume(
          (volume * _videoVolumeBoost).clamp(0.0, 1.0),
        );
        if (resumePosition > Duration.zero) {
          await existingController.seekTo(resumePosition);
        }
        if (shouldKeepPlaying) {
          await existingController.play();
        } else {
          await existingController.pause();
        }
        position = resumePosition;
        _emitPositionUiState();
        notifyListeners();
        return;
      } catch (_) {
        // Fall back to reload path below.
      }
    }

    final generation = ++_loadGeneration;
    await _loadCurrent(currentIndex, generation);
    if (_disposed || generation != _loadGeneration) return;

    final controller = _androidController;
    if (controller != null) {
      try {
        if (resumePosition > Duration.zero) {
          await controller.seekTo(resumePosition);
        }
        if (!shouldKeepPlaying) {
          await controller.pause();
        }
      } catch (_) {}
    }

    notifyListeners();
  }

  // --- Playback controls ----------------------------------------------------

  List<int> _getPlaybackCandidates({MediaType? only}) {
    final scope = _folderItemCount > 0 ? _folderItemCount : library.length;
    final candidates = library
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

    candidates.sort((left, right) {
      final leftDisliked = _disliked.contains(library[left].path);
      final rightDisliked = _disliked.contains(library[right].path);
      if (leftDisliked != rightDisliked) {
        return leftDisliked ? 1 : -1;
      }
      return left.compareTo(right);
    });
    return candidates;
  }

  List<int> _weightedShuffleCandidates(List<int> candidates) {
    if (candidates.isEmpty) return candidates;
    final weighted = <int>[];
    for (final index in candidates) {
      weighted.add(index);
      if (!_disliked.contains(library[index].path)) {
        weighted.add(index);
        weighted.add(index);
      }
    }
    weighted.shuffle(_random);
    return weighted;
  }

  Future<void> togglePlay() async {
    if (_disposed) return;
    if (isVideo) {
      if (_videoBackgroundAudioMode && _audio != null) {
        _audio!.playing ? await _audio!.pause() : await _audio!.play();
        notifyListeners();
        return;
      }
      if (_desktopVideoBackgroundAudioMode && _audioMkPlayer != null) {
        await (_audioMkPlayer!.state.playing
            ? _audioMkPlayer!.pause()
            : _audioMkPlayer!.play());
        notifyListeners();
        return;
      }
      if (_useMediaKit && _mkPlayer != null) {
        await (_mkPlayer!.state.playing ? _mkPlayer!.pause() : _mkPlayer!.play());
      } else if (_androidController != null) {
        _androidController!.value.isPlaying
            ? await _androidController!.pause()
            : await _androidController!.play();
      }
    } else {
      if (_audio != null) {
        try {
          _audio!.playing ? await _audio!.pause() : await _audio!.play();
        } catch (e) {
          debugPrint('just_audio togglePlay error: $e');
          try {
            final item = currentItem;
            if (item != null && item.type == MediaType.audio) {
              final localPath = await _resolveLocalPath(item.path);
              if (localPath.startsWith('http') || localPath.startsWith('content://')) {
                await _audio!.setUrl(localPath);
              } else {
                await _audio!.setFilePath(localPath);
              }
              await _audio!.setVolume(volume);
              await _audio!.play();
            }
          } catch (_) {}
        }
      } else if (_useMediaKit) {
        final player = _audioMkPlayer ?? _mkPlayer;
        if (player != null) {
          await _audioLock.acquire();
          try {
            await (player.state.playing ? player.pause() : player.play());
          } finally {
            _audioLock.release();
          }
        }
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
      if (_videoBackgroundAudioMode && _audio != null) {
        try {
          await _audio!.seek(d);
          _backgroundVideoResumePosition = d;
        } catch (e) {
          debugPrint('background video seek error: $e');
        }
        position = d;
        _emitPositionUiState();
        _scheduleNotify();
        return;
      }
      if (_desktopVideoBackgroundAudioMode && _audioMkPlayer != null) {
        try {
          await _audioMkPlayer!.seek(d);
          _backgroundVideoResumePosition = d;
        } catch (e) {
          debugPrint('desktop background video seek error: $e');
        }
        position = d;
        _emitPositionUiState();
        _scheduleNotify();
        return;
      }
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
      if (_audio != null) {
        debugPrint('Seeking just_audio to $d');
        try {
          await _audio!.seek(d);
        } catch (e) {
          debugPrint('just_audio seek error: $e');
        }
      } else if (_useMediaKit) {
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
      } else {
        debugPrint('No audio player available to seek');
      }
    }

    position = d;
    _emitPositionUiState();

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

  void _resetSeekInteractionState() {
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = null;
    _isSeeking = false;
    _seekPreviewPosition = null;
    _pendingSeekTarget = null;
    _emitPositionUiState();
  }

  void beginSeekInteraction() {
    if (_disposed) return;
    _isSeeking = true;
    _seekPreviewPosition = position;
    _pendingSeekTarget = position;
    _emitPositionUiState();
  }

  void previewSeekInteraction(Duration d) {
    if (_disposed) return;
    _isSeeking = true;
    _seekPreviewPosition = d;
    _pendingSeekTarget = d;
    _emitPositionUiState();

    // For video we only preview while dragging and commit on release.
    // Repeated live seeks can make timeline updates appear stuck/out of sync.
    if (currentItem?.type == MediaType.video) {
      _seekDebounceTimer?.cancel();
      _seekDebounceTimer = null;
      return;
    }

    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      final target = _pendingSeekTarget;
      if (target != null && !_disposed) {
        unawaited(seek(target));
      }
    });
  }

  Future<void> endSeekInteraction() async {
    if (_disposed) return;
    final target = _pendingSeekTarget ?? _seekPreviewPosition;
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = null;
    if (target != null) {
      await seek(target);
    }
    // Always clear seek UI state explicitly. When paused, some backends may
    // not emit a position stream event after seek, leaving the slider "stuck".
    _isSeeking = false;
    _seekPreviewPosition = null;
    _pendingSeekTarget = null;
    _emitPositionUiState();
  }

  Future<void> next({MediaType? only}) async {
    if (library.isEmpty) return;
    final queuedIndex = _popNextQueuedIndex();
    if (queuedIndex != null) {
      await _selectInternal(queuedIndex, fromHistory: false);
      return;
    }
    var candidates = _getPlaybackCandidates(only: only);
    if (candidates.isEmpty && only != null) {
      // If the current filter yields nothing (e.g. songs-only while in a video
      // folder), fall back to whatever is actually available.
      candidates = _getPlaybackCandidates(only: null);
    }
    if (candidates.isEmpty) return;
    int nextIndex;
    if (shuffle) {
      final fresh = candidates
          .where((i) => i != currentIndex && !_recentlyPlayed.contains(i))
          .toList();
      final basePool = fresh.isNotEmpty
          ? fresh
          : candidates.where((i) => i != currentIndex).toList();
      final weighted = _weightedShuffleCandidates(basePool);
      nextIndex = weighted.isEmpty
          ? candidates.first
          : weighted[_random.nextInt(weighted.length)];
    } else {
      final pos = candidates.indexOf(currentIndex);
      nextIndex = pos >= 0 ? candidates[(pos + 1) % candidates.length] : candidates.first;
    }
    await _selectInternal(nextIndex, fromHistory: false);
  }

  int? _popNextQueuedIndex() {
    while (manualQueue.isNotEmpty) {
      final nextIdx = manualQueue.removeAt(0);
      _manualQueueBase.remove(nextIdx);
      if (nextIdx >= 0 && nextIdx < library.length) {
        return nextIdx;
      }
    }
    return null;
  }

  Future<void> previous({MediaType? only}) async {
    if (library.isEmpty) return;
    if (_historyCursor > 0 && _historyCursor < _playHistory.length) {
      _historyCursor--;
      final previousIndex = _playHistory[_historyCursor];
      if (previousIndex >= 0 && previousIndex < library.length) {
        await _selectInternal(previousIndex, fromHistory: true);
        return;
      }
    }
    var candidates = _getPlaybackCandidates(only: only);
    if (candidates.isEmpty && only != null) {
      // If the current filter yields nothing (e.g. songs-only while in a video
      // folder), fall back to whatever is actually available.
      candidates = _getPlaybackCandidates(only: null);
    }
    if (candidates.isEmpty) return;
    int prevIndex;
    if (shuffle) {
      final weighted = _weightedShuffleCandidates(
        candidates.where((i) => i != currentIndex).toList(),
      );
      prevIndex = weighted.isEmpty
          ? candidates.first
          : weighted[_random.nextInt(weighted.length)];
    } else {
      final pos = candidates.indexOf(currentIndex);
      prevIndex = pos >= 0
          ? candidates[(pos - 1 + candidates.length) % candidates.length]
          : candidates.last;
    }
    await _selectInternal(prevIndex, fromHistory: false);
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
    if (_videoBackgroundAudioMode && _audio != null) {
      _runOnMainThread(() => _audio!.setVolume(volume));
    }
  }


  // Post a call to the main isolate. microtask is always processed on the
  // main Dart thread regardless of whether a frame is being rendered.
  void _runOnMainThread(VoidCallback fn) {
    Future.microtask(fn);
  }

  // --- Queue ----------------------------------------------------------------

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
    final queuedIndex = _popNextQueuedIndex();
    if (queuedIndex != null) {
      select(queuedIndex);
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

  // --- Playback mode / prefs ------------------------------------------------

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
        return;
      case PlaybackMode.videos:
        activeTabFilter = MediaType.video;
        favouritesOnly = false;
        return;
      case PlaybackMode.favourites:
        activeTabFilter = null;
        favouritesOnly = true;
        return;
      case PlaybackMode.favouriteSongs:
        activeTabFilter = MediaType.audio;
        favouritesOnly = true;
        return;
      case PlaybackMode.favouriteVideos:
        activeTabFilter = MediaType.video;
        favouritesOnly = true;
        return;
      case PlaybackMode.all:
        activeTabFilter = null;
        favouritesOnly = false;
        return;
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
    _disliked = (prefs.getStringList('player_disliked') ?? []).toSet();

    _favouriteCache.clear();
    for (final raw in prefs.getStringList('player_favourites_cache') ?? []) {
      final parts = raw.split('\t');
      if (parts.length >= 2) {
        final path = parts[0];
        final type = parts[1] == 'v' ? MediaType.video : MediaType.audio;
        final title = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
        final artist = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
        final genre = parts.length > 4 && parts[4].isNotEmpty ? parts[4] : null;
        final modifiedAt = parts.length > 5 ? DateTime.tryParse(parts[5]) : null;
        _favouriteCache[path] = MediaItem(
          path,
          type,
          title: title,
          artist: artist,
          genre: genre,
          modifiedAt: modifiedAt,
        );
      }
    }
    _loadFavouriteThumbsFromDisk();
    notifyListeners();
  }

  String? _extractGenre(dynamic tag) {
    try {
      final raw = (tag as dynamic).genre;
      if (raw == null) return null;
      if (raw is Iterable) {
        final values = raw
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList();
        return values.isEmpty ? null : values.join(', ');
      }
      final text = raw.toString().trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  DateTime? _modifiedAtForPath(String path) {
    try {
      return File(path).statSync().modified;
    } catch (_) {
      return null;
    }
  }

  bool hasPlayedPath(String path) {
    final historyPaths = _playHistory
        .where((index) => index >= 0 && index < library.length)
        .map((index) => library[index].path)
        .toSet();
    if (historyPaths.contains(path)) return true;
    return _recentlyPlayed
        .where((index) => index >= 0 && index < library.length)
        .map((index) => library[index].path)
        .contains(path);
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

  // --- Audio handler (Android) ----------------------------------------------

  Future<void> _initAudioHandler() async {
    // _audio is non-null when this is called (guarded by caller).
    _audioHandler = await initAudioService(_audio!);
    if (_audioHandler != null) {
      _audioHandler!.onSkipToNext = () => next(only: activeTabFilter);
      _audioHandler!.onSkipToPrevious = () => previous(only: activeTabFilter);
      final pending = _pendingNotificationItem;
      if (pending != null) {
        _updateMediaNotification(pending);
      }
    }
  }

  void _updateMediaNotification(MediaItem item) {
    _pendingNotificationItem = item;
    final sequence = _notificationGuard.nextToken();
    if (_audioHandler == null) return;
    unawaited(_pushMediaNotification(item, sequence));
  }

  Future<void> _pushMediaNotification(MediaItem item, int sequence) async {
    if (_audioHandler == null) return;
    if (!_notificationGuard.isCurrent(sequence)) return;

    Uint8List? thumb = item.thumbnailData;
    if ((thumb == null || thumb.isEmpty) && item.path.isNotEmpty) {
      try {
        thumb = await _loadThumbFromCache(item.path);
      } catch (_) {}
    }
    if (!_notificationGuard.isCurrent(sequence)) return;

    Uri? artUri;
    try {
      final cacheDir = await getTemporaryDirectory();
      final artFile = File(
        '${cacheDir.path}${Platform.pathSeparator}now_playing_art_$sequence.png',
      );
      await artFile.writeAsBytes(
        (thumb != null && thumb.isNotEmpty) ? thumb : _transparentArtPng,
        flush: true,
      );
      artUri = artFile.uri;
    } catch (_) {}
    if (!_notificationGuard.isCurrent(sequence)) return;

    final current = currentItem;
    if (current == null || current.path != item.path) {
      return;
    }

    await _audioHandler!.updateMediaItem(
      audio_svc.MediaItem(
        id: item.path,
        title: item.title ?? p.basenameWithoutExtension(item.path),
        artist: item.artist ?? '',
        duration: item.duration ?? duration,
        artUri: artUri,
      ),
    );
  }

  // --- Directory watcher ----------------------------------------------------

  void _startDirectoryWatcher(List<MediaItem> items) {
    _dirWatcher?.cancel();
    _dirWatcher = null;
    _watchedDirPath = null;

    if (kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isWindows) {
      return;
    }
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
        // Ignore noisy content writes (common during torrent seeding) to avoid
        // expensive full-library rescans while files are being updated.
        final shouldRescan =
            (event.type & FileSystemEvent.create) != 0 ||
            (event.type & FileSystemEvent.delete) != 0 ||
            (event.type & FileSystemEvent.move) != 0;
        if (!shouldRescan) return;
        final ext = p.extension(event.path).toLowerCase();
        if (!_mediaExtensions.contains(ext)) return;
        debounce?.cancel();
        debounce = Timer(const Duration(seconds: 2), () {
          if (!_disposed) {
            unawaited(_refreshLibraryFromDisk());
          }
        });
      });
    } catch (e) {
      debugPrint('Directory watcher error: $e');
    }
  }

  Future<void> _refreshLibraryFromDisk() async {
    if (_libraryRefreshInProgress) {
      _libraryRefreshQueued = true;
      return;
    }
    _libraryRefreshInProgress = true;
    final dirPath = _watchedDirPath;
    try {
      if (dirPath == null) return;
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;

      final files = <MediaItem>[];
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (_disposed) return;
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!_mediaExtensions.contains(ext)) continue;
        final isVideo = {
          '.mp4',
          '.mkv',
          '.avi',
          '.webm',
          '.mov',
          '.wmv',
          '.flv',
          '.m4v',
        }.contains(ext);
        files.add(
          MediaItem(
            entity.path,
            isVideo ? MediaType.video : MediaType.audio,
            title: p.basenameWithoutExtension(entity.path),
            modifiedAt: _modifiedAtForPath(entity.path),
          ),
        );
      }

      final currentPaths = library
          .take(_folderItemCount)
          .map((e) => e.path)
          .toSet();
      final newPaths = files.map((e) => e.path).toSet();
      if (currentPaths.length == newPaths.length &&
          currentPaths.containsAll(newPaths)) {
        return;
      }

      await setLibrary(files);
    } finally {
      _libraryRefreshInProgress = false;
      if (_libraryRefreshQueued && !_disposed) {
        _libraryRefreshQueued = false;
        unawaited(_refreshLibraryFromDisk());
      }
    }
  }

  // --- Video thumbnail generation -------------------------------------------

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
          // Plugin not available on this platform - ignore and continue.
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
          debugPrint('Skipping rapid thumb open - too soon');
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

  // --- Helpers --------------------------------------------------------------

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

  Future<void> _handleMalformedMedia(
    String path,
    Object error, {
    String context = 'playback',
  }) async {
    if (_disposed) return;
    if (_ignoredBrokenMediaPaths.contains(path)) return;
    _ignoredBrokenMediaPaths.add(path);

    debugPrint('Malformed media detected in $context for $path: $error');

    if (!path.startsWith('content://') &&
        !path.startsWith('http://') &&
        !path.startsWith('https://')) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          debugPrint('Deleted malformed media file: $path');
        }
      } catch (e) {
        debugPrint('Unable to delete malformed media file $path: $e');
      }
    }

    final index = library.indexWhere((item) => item.path == path);
    if (index < 0) {
      _scheduleNotify();
      return;
    }

    final wasCurrent = index == currentIndex;
    library.removeAt(index);
    _rebaseStateAfterRemoval(index);

    if (library.isEmpty) {
      await _stopPlaybackBestEffort();
      currentIndex = 0;
      position = Duration.zero;
      duration = null;
      _folderItemCount = 0;
      _emitPositionUiState();
      _scheduleNotify();
      return;
    }

    if (wasCurrent) {
      currentIndex = index.clamp(0, library.length - 1);
      final generation = ++_loadGeneration;
      unawaited(_loadCurrent(currentIndex, generation));
    }
    _scheduleNotify();
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
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = null;
    _positionUiController.close();
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

    // Prevent pending debounce seeks from a previously selected track from
    // being applied after direct file selection.
    _resetSeekInteractionState();

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
      try { await _safeStopAudio(); } catch (_) {}
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
              debugPrint('Skipping rapid audioMk open - too soon');
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
            await _handleMalformedMedia(path, e, context: 'direct media_kit audio load');
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
                await _handleMalformedMedia(path, e, context: 'direct audio load');
              }
            });
          }
        }
      } else {
        // Video: prefer media_kit on supported platforms.
        if (_useMediaKit && _mkPlayer != null) {
          final now = DateTime.now();
          if (_lastMkOpenTime != null && now.difference(_lastMkOpenTime!).inMilliseconds < 350) {
            debugPrint('Skipping rapid mk open (playFileDirect) - too soon');
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
      await _handleMalformedMedia(path, e, context: 'direct playback');
    }
  }
}

// --- Helper types for the All tab --------------------------------------------

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


// --- Persistent video widget --------------------------------------------------

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
    if (Platform.isWindows) {
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

    return Focus(
      canRequestFocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.expand(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.background,
            child: widget.ready
                ? Stack(
                    fit: StackFit.loose,
                    children: [
                      Center(child: child),
                      Positioned(
                        // overflow-fix: keep top-right overlay control inside safe insets.
                        top: mq.padding.top + 10,
                        right: mq.padding.right + 10,
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
      ),
    );
  }
}

// --- Theme constants ----------------------------------------------------------

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
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72);
}

// --- Root screen --------------------------------------------------------------

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
  with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  MediaSortOrder _sortOrder = MediaSortOrder.newestFirst;
  MediaType? _activeMediaType;
  final Set<String> _activeGenres = <String>{};
  bool _uiPrefsLoaded = false;
  bool _isFullScreen = false;

  bool get _usesNativeWindowFullscreen =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  // One scroll controller per tab to avoid cross-tab controller conflicts.
  final _scrollControllers = List.generate(4, (_) => ScrollController());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() { if (!_tabController.indexIsChanging) setState(() {}); });
    if (_usesNativeWindowFullscreen) {
      unawaited(_syncFullscreenState());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_uiPrefsLoaded) return;
    _uiPrefsLoaded = true;
    final prefs = context.read<PlayerState>().prefs;
    _sortOrder = MediaSortOrder.values[
        (prefs.getInt('player_sort_order') ?? 0).clamp(0, MediaSortOrder.values.length - 1)];
    final mediaTypeFilter = prefs.getString('player_filter_media_type');
    _activeMediaType = switch (mediaTypeFilter) {
      'audio' => MediaType.audio,
      'video' => MediaType.video,
      _ => null,
    };
    _activeGenres.addAll(prefs.getStringList('player_filter_genres') ?? const []);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    unawaited(context.read<PlayerState>().onAppLifecycleChanged(state));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_exitFullScreen());
    _tabController.dispose();
    _searchController.dispose();
    for (final sc in _scrollControllers) { sc.dispose(); }
    super.dispose();
  }

  Future<void> _syncFullscreenState() async {
    if (!_usesNativeWindowFullscreen) return;
    try {
      final isFullScreen = await windowManager.isFullScreen();
      if (mounted && _isFullScreen != isFullScreen) {
        setState(() => _isFullScreen = isFullScreen);
      }
    } catch (_) {}
  }

  Future<void> _enterFullScreen() async {
    if (_isFullScreen) return;
    if (_usesNativeWindowFullscreen) {
      await toggleDesktopFullScreen();
      await _syncFullscreenState();
      return;
    }
    _isFullScreen = true;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitFullScreen() async {
    if (_usesNativeWindowFullscreen) {
      try {
        if (await windowManager.isFullScreen()) {
          await toggleDesktopFullScreen();
        }
      } finally {
        await _syncFullscreenState();
      }
      return;
    }
    if (!_isFullScreen) return;
    _isFullScreen = false;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Future<void> _toggleFullScreen() async {
    if (_isFullScreen) {
      await _exitFullScreen();
    } else {
      await _enterFullScreen();
    }
    if (mounted) {
      setState(() {});
    }
  }

  bool _matchesSearch(MediaItem item) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    final title = (item.title ?? p.basenameWithoutExtension(item.path)).toLowerCase();
    final artist = (item.artist ?? '').toLowerCase();
    return title.contains(q) || artist.contains(q);
  }

  List<MapEntry<int, MediaItem>> _sortAndFilterEntries(
    Iterable<MapEntry<int, MediaItem>> source,
    PlayerState state,
  ) {
    final filtered = source.where((entry) {
      final item = entry.value;
      if (!_matchesSearch(item)) return false;
      if (_activeMediaType != null && item.type != _activeMediaType) return false;
      if (_activeGenres.isNotEmpty) {
        final genres = (item.genre ?? '')
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet();
        if (genres.intersection(_activeGenres).isEmpty) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      switch (_sortOrder) {
        case MediaSortOrder.oldestFirst:
          return (a.value.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.value.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
        case MediaSortOrder.titleAZ:
          return _sortTitleOf(a.value).compareTo(_sortTitleOf(b.value));
        case MediaSortOrder.titleZA:
          return _sortTitleOf(b.value).compareTo(_sortTitleOf(a.value));
        case MediaSortOrder.shortestDuration:
          return (a.value.duration ?? Duration.zero)
              .compareTo(b.value.duration ?? Duration.zero);
        case MediaSortOrder.newestFirst:
          return (b.value.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.value.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      }
    });
    return filtered;
  }

  String _sortTitleOf(MediaItem item) =>
      (item.title ?? p.basenameWithoutExtension(item.path)).toLowerCase();

  List<String> _availableGenres(PlayerState state) {
    final genres = <String>{};
    for (final item in state.library) {
      final raw = item.genre;
      if (raw == null || raw.trim().isEmpty) continue;
      for (final value in raw.split(',')) {
        final genre = value.trim();
        if (genre.isNotEmpty) genres.add(genre);
      }
    }
    final result = genres.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  void _saveUiPrefs(PlayerState state) {
    final prefs = state.prefs;
    prefs.setInt('player_sort_order', _sortOrder.index);
    if (_activeMediaType == null) {
      prefs.remove('player_filter_media_type');
    } else {
      prefs.setString('player_filter_media_type', _activeMediaType == MediaType.audio ? 'audio' : 'video');
    }
    prefs.setStringList('player_filter_genres', _activeGenres.toList()..sort());
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
          return MediaItem(
            f.path,
            isVideo ? MediaType.video : MediaType.audio,
            title: p.basenameWithoutExtension(f.path),
            modifiedAt: f.statSync().modified,
          );
        })
        .toList();

    if (mounted) await context.read<PlayerState>().setLibrary(items);
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();
    final screenWidth = MediaQuery.of(context).size.width;
    final searchBarHeight = screenWidth < 600 ? 128.0 : 88.0;

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
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _FixedHeightSliverDelegate(
                    height: 260.0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      height: 260.0,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.background),
                      child: _VideoPane(
                        mkController: state.videoController,
                        androidController: state.androidVideoController,
                        visible: true,
                        ready: state.videoReady,
                        isFullScreen: _isFullScreen,
                        onTap: state.togglePlay,
                        onToggleFullScreen: _toggleFullScreen,
                      ),
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
              SliverPersistentHeader(
                pinned: true,
                delegate: _FixedHeightSliverDelegate(
                  height: 48,
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
              ),
              if (!(isMobile && showVideoPane))
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _FixedHeightSliverDelegate(
                    height: searchBarHeight,
                    child: _buildSearchBar(state),
                  ),
                ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _AllTab(
                entries: _sortAndFilterEntries(
                  state.library.asMap().entries.take(state.folderItemCount > 0 ? state.folderItemCount : state.library.length),
                  state,
                ),
                state: state,
                scrollCtl: _scrollControllers[0],
                onTap: _onTrackTap,
              ),
              _SongsTab(
                entries: _sortAndFilterEntries(state.audioEntries, state),
                state: state,
                scrollCtl: _scrollControllers[1],
                onTap: _onTrackTap,
              ),
              _VideosTab(
                entries: _sortAndFilterEntries(state.videoEntries, state),
                state: state,
                scrollCtl: _scrollControllers[2],
                onTap: _onTrackTap,
              ),
              _FavouritesTab(
                entries: _sortAndFilterEntries(state.favouriteEntries, state),
                state: state,
                scrollCtl: _scrollControllers[3],
                onTap: _onTrackTap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // BUG 1 FIX: all taps go through this single method which immediately captures
  // the index and calls select() - no intermediate setState() that could shift indices.
  void _onTrackTap(PlayerState state, int index) {
    // Play by file path to avoid any index/id races in the UI layer or native
    // plugins. This ensures taps map directly to the file the user tapped.
    final idx = index;
    if (idx >= 0 && idx < state.library.length) {
      final path = state.library[idx].path;
      state.playFileDirect(path);
    }
  }

  QueueScope _queueScopeForTab(int tabIndex) {
    switch (tabIndex) {
      case 1:
        return QueueScope.songs;
      case 2:
        return QueueScope.videos;
      case 3:
        return QueueScope.favourites;
      default:
        return QueueScope.all;
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
            PopupMenuButton<String>(
              tooltip: 'Queue actions',
              icon: Icon(Icons.queue_music_rounded,
                  color: Theme.of(context).colorScheme.onSurface),
              onSelected: (value) {
                final state = context.read<PlayerState>();
                switch (value) {
                  case 'current':
                    state.enqueueScope(_queueScopeForTab(_tabController.index));
                    break;
                  case 'all':
                    state.enqueueScope(QueueScope.all);
                    break;
                  case 'songs':
                    state.enqueueScope(QueueScope.songs);
                    break;
                  case 'videos':
                    state.enqueueScope(QueueScope.videos);
                    break;
                  case 'favourites':
                    state.enqueueScope(QueueScope.favourites);
                    break;
                  case 'favSongs':
                    state.enqueueScope(QueueScope.favSongs);
                    break;
                  case 'favVideos':
                    state.enqueueScope(QueueScope.favVideos);
                    break;
                  case 'clear':
                    state.clearQueue();
                    break;
                }
                if (mounted) {
                  Snack.show(context, 'Queue updated', level: SnackLevel.info);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'current', child: Text('Queue current tab')),
                PopupMenuItem(value: 'all', child: Text('Queue all')),
                PopupMenuItem(value: 'songs', child: Text('Queue songs')),
                PopupMenuItem(value: 'videos', child: Text('Queue videos')),
                PopupMenuItem(value: 'favourites', child: Text('Queue favourites')),
                PopupMenuItem(value: 'favSongs', child: Text('Queue favourite songs')),
                PopupMenuItem(value: 'favVideos', child: Text('Queue favourite videos')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'clear', child: Text('Clear queue')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(PlayerState state) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 600;
    final genres = _availableGenres(state);

    Widget sortButton() {
      return PopupMenuButton<MediaSortOrder>(
        tooltip: 'Sort',
        icon: const Icon(Icons.sort_rounded),
        initialValue: _sortOrder,
        onSelected: (value) {
          setState(() => _sortOrder = value);
          _saveUiPrefs(state);
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: MediaSortOrder.newestFirst, child: Text('Newest first')),
          PopupMenuItem(value: MediaSortOrder.oldestFirst, child: Text('Oldest first')),
          PopupMenuItem(value: MediaSortOrder.titleAZ, child: Text('Title A-Z')),
          PopupMenuItem(value: MediaSortOrder.titleZA, child: Text('Title Z-A')),
          PopupMenuItem(value: MediaSortOrder.shortestDuration, child: Text('Shortest first')),
        ],
      );
    }

    Widget filterChips() {
      // Media type filters are handled elsewhere in the UI; only show
      // genre chips here to avoid duplication and visual clutter.
      final chips = <Widget>[];
      for (final genre in genres)
        chips.add(FilterChip(
          label: Text(genre),
          selected: _activeGenres.contains(genre),
          onSelected: (value) {
            setState(() {
              if (value) {
                _activeGenres.add(genre);
              } else {
                _activeGenres.remove(genre);
              }
            });
            _saveUiPrefs(state);
          },
        ));
      if (chips.isEmpty) return const SizedBox.shrink();
      return Wrap(spacing: 8, runSpacing: 8, children: chips);
    }

    final searchField = TextField(
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
    );

    if (isWide) {
      return Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 8),
                sortButton(),
              ],
            ),
            const SizedBox(height: 8),
            filterChips(),
          ],
        ),
      );
    }

    // Mobile: only show search and sort, NO filter chips to avoid clutter
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(child: searchField),
          const SizedBox(width: 8),
          sortButton(),
        ],
      ),
    );
  }

  // --- Now Playing bar ------------------------------------------------------

  Widget _buildNowPlaying(PlayerState state) {
    final item = state.currentItem;
    if (item == null) return const SizedBox.shrink();

    final title = item.title ?? p.basenameWithoutExtension(item.path);
    final artist = item.artist ?? '';
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? cs.surfaceContainerHigh
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: state.isPlaying
              ? cs.primary.withValues(alpha: 0.42)
              : cs.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // -- Track info --
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
                          // Type badge - clear visual distinction between audio and video
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
                _TrackMenuButton(
                  state: state,
                  entry: MapEntry(state.currentIndex, item),
                ),
              ],
            ),
          ),

          // -- Seek bar --
          _PositionWidget(state: state, formatDur: _fmtDur),

          // -- Playback controls --
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

          // -- Volume --
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

// --- Shared UI components ---------------------------------------------------

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
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
      ),
      child: Icon(icon, size: size * 0.55, color: Theme.of(context).colorScheme.onSurface.withAlpha(153)),
    );
  }
}

class _PositionWidget extends StatelessWidget {
  final PlayerState state;
  final String Function(Duration) formatDur;

  const _PositionWidget({required this.state, required this.formatDur});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionUiState>(
      stream: state.positionUiStream,
      initialData: PositionUiState(
        position: state.position,
        duration: state.duration ?? Duration.zero,
        isSeeking: false,
      ),
      builder: (context, snapshot) {
        final ui = snapshot.data ??
            PositionUiState(
              position: state.position,
              duration: state.duration ?? Duration.zero,
              isSeeking: false,
            );
        final dur = ui.duration;
        final pos = ui.position;
        final progress = dur.inMilliseconds > 0
            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Text(
                formatDur(pos),
                style: TextStyle(
                  fontSize: 11,
                  color: _PlayerTheme.sub(context),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: progress,
                    activeColor: _PlayerTheme.accent,
                    inactiveColor: _PlayerTheme.accentDim,
                    onChangeStart: dur.inMilliseconds > 0
                        ? (_) => state.beginSeekInteraction()
                        : null,
                    onChanged: dur.inMilliseconds > 0
                        ? (v) => state.previewSeekInteraction(
                              Duration(
                                milliseconds: (v * dur.inMilliseconds).round(),
                              ),
                            )
                        : null,
                    onChangeEnd: dur.inMilliseconds > 0
                        ? (_) => unawaited(state.endSeekInteraction())
                        : null,
                  ),
                ),
              ),
              if (ui.isSeeking)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _PlayerTheme.accent,
                    ),
                  ),
                ),
              Text(
                formatDur(dur),
                style: TextStyle(
                  fontSize: 11,
                  color: _PlayerTheme.sub(context),
                ),
              ),
            ],
          ),
        );
      },
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
        color: theme.colorScheme.primary.withValues(alpha: 0.18),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final iconColor = active ? cs.onPrimaryContainer : theme.iconTheme.color;

    return Tooltip(
      message: tooltip ?? '',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? cs.primary.withValues(alpha: 0.58)
                : Colors.transparent,
          ),
        ),
        child: IconButton(
          iconSize: size,
          icon: Icon(icon, color: iconColor),
          onPressed: onPressed,
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

enum _TrackMenuAction { queue, favourite, dislike, delete }

class _TrackMenuButton extends StatelessWidget {
  final PlayerState state;
  final MapEntry<int, MediaItem> entry;

  const _TrackMenuButton({required this.state, required this.entry});

  @override
  Widget build(BuildContext context) {
    final item = entry.value;
    final index = entry.key;
    final isFavourite = state.isFavourite(item.path);
    final isDisliked = state.isDisliked(item.path);

    return PopupMenuButton<_TrackMenuAction>(
      tooltip: 'Track actions',
      icon: Icon(Icons.more_vert_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
      onSelected: (action) async {
        switch (action) {
          case _TrackMenuAction.queue:
            state.enqueue(index);
            break;
          case _TrackMenuAction.favourite:
            state.toggleFavourite(item.path);
            break;
          case _TrackMenuAction.dislike:
            state.toggleDislike(item.path);
            break;
          case _TrackMenuAction.delete:
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Delete file?'),
                // overflow-fix: long file names can overflow dialog content width.
                content: SingleChildScrollView(
                  child: Text(
                    'This permanently deletes "${item.title ?? p.basename(item.path)}" from disk.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              final deleted = await state.deleteMediaItem(item.path);
              if (context.mounted) {
                Snack.show(
                  context,
                  deleted ? 'File deleted' : 'Could not delete file',
                  level: deleted ? SnackLevel.info : SnackLevel.error,
                );
              }
            }
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _TrackMenuAction.queue,
          child: ListTile(
            leading: Icon(Icons.queue_music_rounded),
            title: Text('Add to queue'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _TrackMenuAction.favourite,
          child: ListTile(
            leading: Icon(isFavourite ? Icons.star_rounded : Icons.star_border_rounded),
            title: Text(isFavourite ? 'Remove favourite' : 'Add favourite'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _TrackMenuAction.dislike,
          child: ListTile(
            leading: Icon(isDisliked ? Icons.thumb_down_alt_rounded : Icons.thumb_down_alt_outlined),
            title: Text(isDisliked ? 'Undo dislike' : 'Dislike'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: _TrackMenuAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline_rounded),
            title: Text('Delete file'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

// --- Tab widgets (each is its own StatelessWidget to limit rebuild scope) -----

/// BUG 2 FIX: each tab is its own widget so rebuilds from thumbnail loads only
/// repaint the visible tab, not the entire screen.

class _AllTab extends StatelessWidget {
  final List<MapEntry<int, MediaItem>> entries;
  final PlayerState state;
  final ScrollController scrollCtl;
  final void Function(PlayerState, int) onTap;

  const _AllTab({
    required this.entries,
    required this.state,
    required this.scrollCtl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _EmptyHint(message: state.library.isEmpty
          ? 'Your library is empty.\nTap the folder icon to open a folder or download media.'
          : 'No results for this search.');
    }

    // Keep visual parity with Songs/Videos/Fav by reusing the same grid widget.
    return _MediaGrid(entries: entries, state: state, onTap: onTap);
  }
}

class _SongsTab extends StatelessWidget {
  final List<MapEntry<int, MediaItem>> entries;
  final PlayerState state;
  final ScrollController scrollCtl;
  final void Function(PlayerState, int) onTap;

  const _SongsTab({required this.entries, required this.state, required this.scrollCtl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const _EmptyHint(message: 'No songs found.');
    return _MediaGrid(entries: entries, state: state, onTap: onTap);
  }
}

class _VideosTab extends StatelessWidget {
  final List<MapEntry<int, MediaItem>> entries;
  final PlayerState state;
  final ScrollController scrollCtl;
  final void Function(PlayerState, int) onTap;

  const _VideosTab({required this.entries, required this.state, required this.scrollCtl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const _EmptyHint(message: 'No videos found.');
    return _MediaGrid(entries: entries, state: state, onTap: onTap);
  }
}

class _FavouritesTab extends StatelessWidget {
  final List<MapEntry<int, MediaItem>> entries;
  final PlayerState state;
  final ScrollController scrollCtl;
  final void Function(PlayerState, int) onTap;

  const _FavouritesTab({required this.entries, required this.state, required this.scrollCtl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyHint(message: 'No favourites yet.\nTap ★ on any track to add it here.');
    }
    return _MediaGrid(entries: entries, state: state, onTap: onTap);
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
    final crossAxisCount = width < 500
        ? 2
        : width < 900
            ? 3
            : width < 1200
                ? 4
                : width < 1600
                    ? 5
                    : 6;
    return GridView.builder(
      shrinkWrap: false,
      physics: null,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: width < 900 ? 0.82 : 0.9,
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
                    child: state.thumbnailForItem(item, size: 0, expand: true) ?? Container(color: cs.surfaceContainerHighest),
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
                          const SizedBox(width: 4),
                          _TrackMenuButton(state: state, entry: entry),
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

// --- Reusable tile / card components -----------------------------------------

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

class _FixedHeightSliverDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _FixedHeightSliverDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: height, child: child);
  }

  @override
  bool shouldRebuild(covariant _FixedHeightSliverDelegate oldDelegate) {
    return height != oldDelegate.height || child != oldDelegate.child;
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
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.11),
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
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.equalizer, color: Colors.green),
                const SizedBox(width: 8),
                _TrackMenuButton(state: state, entry: entry),
              ],
            )
          : _TrackMenuButton(state: state, entry: entry),
      onTap: () => onTap(state, index),
    );
  }
}


