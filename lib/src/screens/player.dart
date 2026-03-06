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
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_player/video_player.dart';
import '../services/platform_dirs.dart';
import '../services/audio_handler.dart';
import 'cast_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// IMPORTANT: In your main.dart add these two lines before runApp():
//   WidgetsFlutterBinding.ensureInitialized();
//   MediaKit.ensureInitialized();
// ─────────────────────────────────────────────────────────────────────────────

// ─── Wrapper ──────────────────────────────────────────────────────────────────

/// Wrapper widget that simply displays the screen. Actual state is
/// provided above in the app so it survives navigation/tab switches.
class playerPlayerPage extends StatelessWidget {
  const playerPlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlayerScreen();
  }
}

// ─── Data types ───────────────────────────────────────────────────────────────

enum MediaType { audio, video }

enum RepeatMode { off, one, all }

class MediaItem {
  final String path;
  final MediaType type;
  final String? title;
  final String? artist;
  // Always PNG-encoded after processing — safe for Image.memory everywhere.
  final Uint8List? thumbnailData;

  const MediaItem(this.path, this.type,
      {this.title, this.artist, this.thumbnailData});

  MediaItem copyWith(
          {String? title, String? artist, Uint8List? thumbnailData}) =>
      MediaItem(path, type,
          title: title ?? this.title,
          artist: artist ?? this.artist,
          thumbnailData: thumbnailData ?? this.thumbnailData);
}

// ─── Thumbnail transcoding ───────────────────────────────────────────────────

Future<Uint8List?> _transcodeToSafePng(Uint8List raw,
    {String? mimeType}) async {
  if (raw.length < 4) {
    debugPrint('_transcodeToSafePng: data too short (${raw.length} bytes)');
    return null;
  }

  try {
    img.Image? decoded;

    if (mimeType != null) {
      final mt = mimeType.toLowerCase().trim();
      if (mt.contains('jpeg') || mt.contains('jpg')) {
        decoded = img.decodeJpg(raw);
      } else if (mt.contains('png')) {
        decoded = img.decodePng(raw);
      } else if (mt.contains('webp')) {
        decoded = img.decodeWebP(raw);
      } else if (mt.contains('bmp')) {
        decoded = img.decodeBmp(raw);
      } else if (mt.contains('gif')) {
        decoded = img.decodeGif(raw);
      } else if (mt.contains('tiff') || mt.contains('tif')) {
        decoded = img.decodeTiff(raw);
      }
      if (decoded != null) {
        debugPrint(
            '_transcodeToSafePng: decoded via mime hint "$mimeType" (${raw.length} bytes)');
      }
    }

    if (decoded == null) {
      decoded = _decodeByMagic(raw);
    }

    if (decoded == null) {
      decoded = img.decodeImage(raw);
    }

    if (decoded == null) {
      debugPrint(
          '_transcodeToSafePng: all decoders failed (${raw.length} bytes, mime=$mimeType)');
      return null;
    }

    final thumb = img.copyResize(decoded,
        width: 240, interpolation: img.Interpolation.average);

    return Uint8List.fromList(img.encodePng(thumb));
  } catch (e, st) {
    debugPrint('_transcodeToSafePng exception: $e\n$st');
    return null;
  }
}

img.Image? _decodeByMagic(Uint8List raw) {
  if (raw.length < 4) return null;

  if (raw[0] == 0xFF && raw[1] == 0xD8 && raw[2] == 0xFF) {
    return img.decodeJpg(raw);
  }
  if (raw[0] == 0x89 &&
      raw[1] == 0x50 &&
      raw[2] == 0x4E &&
      raw[3] == 0x47) {
    return img.decodePng(raw);
  }
  if (raw[0] == 0x47 &&
      raw[1] == 0x49 &&
      raw[2] == 0x46 &&
      raw[3] == 0x38) {
    return img.decodeGif(raw);
  }
  if (raw[0] == 0x42 && raw[1] == 0x4D) {
    return img.decodeBmp(raw);
  }
  if (raw.length >= 12 &&
      raw[0] == 0x52 && raw[1] == 0x49 && raw[2] == 0x46 && raw[3] == 0x46 &&
      raw[8] == 0x57 && raw[9] == 0x45 && raw[10] == 0x42 && raw[11] == 0x50) {
    return img.decodeWebP(raw);
  }
  if ((raw[0] == 0x49 && raw[1] == 0x49 && raw[2] == 0x2A && raw[3] == 0x00) ||
      (raw[0] == 0x4D && raw[1] == 0x4D && raw[2] == 0x00 && raw[3] == 0x2A)) {
    return img.decodeTiff(raw);
  }

  return null;
}

// ─── State ────────────────────────────────────────────────────────────────────

class PlayerState with ChangeNotifier {
  final SharedPreferences prefs;

  List<MediaItem> library = [];
  int currentIndex = 0;
  bool shuffle = false;
  RepeatMode repeatMode = RepeatMode.off;
  double volume = 0.5;
  bool isLoading = false;

  /// Which media type the player should stick to when auto-advancing.
  /// Set by the UI based on which tab is active (null = all).
  MediaType? activeTabFilter;

  /// Paths marked as favourites (persisted).
  Set<String> _favourites = {};

  /// Cached metadata for favourite items (survives folder changes).
  Map<String, MediaItem> _favouriteCache = {};

  /// Number of items from the currently loaded folder (excludes appended
  /// cached favourites from other folders).
  int _folderItemCount = 0;

  int get folderItemCount => _folderItemCount;

  /// Volume boost multiplier for video playback (videos are often quieter).
  static const double _videoVolumeBoost = 1.8;

  // Audio — just_audio works fine on all platforms
  final AudioPlayer _audio = AudioPlayer();

  // Android background audio service (media notification + background playback).
  AppAudioHandler? _audioHandler;

  // media_kit is used on Windows/Linux/macOS/iOS.
  // On Android we use the `video_player` plugin (ExoPlayer) instead, because
  // media_kit throws "Unsupported platform: android" at runtime.
  final bool _videoSupported = kIsWeb || !Platform.isAndroid;

  // Created once and reused — never recreate, the Video widget holds a ref.
  Player? _mkPlayer;
  VideoController? _mkController;

  // Android-only: one VideoPlayerController per track, created/disposed each load.
  VideoPlayerController? _androidController;
  // Stored so we can remove it before disposing the controller.
  VoidCallback? _androidListener;

  // Auxiliary player for thumbnail screenshots (desktop/iOS only).
  Player? _thumbPlayer;

  // True once the first video frame has arrived (media_kit) or initialize()
  // has completed (video_player on Android).
  bool _videoReady = false;

  bool _videoCompletionFired = false;
  bool _loadingTrack = false;
  bool _pendingReload = false;
  bool _disposed = false;
  final List<StreamSubscription> _subs = [];

  Duration position = Duration.zero;
  Duration? duration;

  final _random = Random();

  PlayerState(this.prefs) {
    if (_videoSupported) {
      try {
        _mkPlayer = Player();
        _mkController = VideoController(_mkPlayer!);
        _thumbPlayer = Player();
      } catch (e, st) {
        debugPrint('media_kit player creation failed: $e');
        debugPrint('$st');
        _videoReady = false;
        _mkPlayer = null;
        _mkController = null;
        _thumbPlayer = null;
      }
    } else {
      debugPrint('media_kit disabled on Android — using video_player fallback');
    }

    _loadPrefs().then((_) => _applyVolume());

    // Android: initialise background audio service for media notification.
    if (!kIsWeb && Platform.isAndroid) {
      _initAudioHandler();
    }

    // ── Audio streams ──
    _subs.add(_audio.positionStream.listen((pos) {
      if (_disposed) return;
      if (currentItem?.type == MediaType.audio) {
        position = pos;
        notifyListeners();
      }
    }));
    _subs.add(_audio.durationStream.listen((dur) {
      if (_disposed) return;
      if (currentItem?.type == MediaType.audio) {
        duration = dur;
        notifyListeners();
      }
    }));
    _subs.add(_audio.playerStateStream.listen((ps) {
      if (_disposed) return;
      if (ps.processingState == ProcessingState.completed) {
        _handleCompletion();
      }
      notifyListeners();
    }));

    // ── Video streams (media_kit, non-Android only) ──
    if (_videoSupported && _mkPlayer != null) {
      _subs.add(_mkPlayer!.stream.position.listen((pos) {
        if (_disposed) return;
        if (currentItem?.type == MediaType.video) {
          position = pos;
          notifyListeners();
        }
      }));
      _subs.add(_mkPlayer!.stream.duration.listen((dur) {
        if (_disposed) return;
        if (currentItem?.type == MediaType.video) {
          duration = dur;
          notifyListeners();
        }
      }));
      _subs.add(_mkPlayer!.stream.volume.listen((v) {
        if (_disposed) return;
        // media_kit reports the boosted volume — reverse the boost to get the
        // user-facing value.
        final raw = (v / 100).clamp(0.0, 1.0);
        final unboosted = currentItem?.type == MediaType.video
            ? (raw / _videoVolumeBoost).clamp(0.0, 1.0)
            : raw;
        if ((unboosted - volume).abs() > 0.01) {
          volume = unboosted;
          prefs.setDouble('volume', volume);
          notifyListeners();
        }
      }));
      _subs.add(_mkPlayer!.stream.width.listen((w) {
        if (_disposed) return;
        if (currentItem?.type == MediaType.video && (w ?? 0) > 0) {
          if (!_videoReady) {
            _videoReady = true;
            notifyListeners();
          }
        }
      }));
      _subs.add(_mkPlayer!.stream.completed.listen((done) {
        if (_disposed) return;
        if (done &&
            currentItem?.type == MediaType.video &&
            !_videoCompletionFired) {
          _videoCompletionFired = true;
          _handleCompletion();
        }
      }));
    }
  }

  Future<void> _initAudioHandler() async {
    _audioHandler = await initAudioService(_audio);
    if (_audioHandler != null) {
      // Wire skip events from the notification back into PlayerState.
      _audioHandler!.onSkipToNext = () => next(only: MediaType.audio);
      _audioHandler!.onSkipToPrevious = () => previous(only: MediaType.audio);
    }
  }

  /// Push the current track's metadata to the Android media notification.
  void _updateMediaNotification() {
    if (_audioHandler == null) return;
    final item = currentItem;
    if (item == null) return;
    _audioHandler!.updateMediaItem(audio_svc.MediaItem(
      id: item.path,
      title: item.title ?? p.basenameWithoutExtension(item.path),
      artist: item.artist ?? '',
      duration: duration,
    ));
  }

  // ── Getters ──

  MediaItem? get currentItem {
    if (library.isEmpty) return null;
    if (currentIndex < 0 || currentIndex >= library.length) {
      currentIndex = library.isNotEmpty ? 0 : -1;
    }
    return library[currentIndex];
  }

  bool get isVideo => currentItem?.type == MediaType.video;

  // Video is supported on every platform: media_kit on desktop/iOS,
  // video_player on Android.
  bool get videoSupported => true;

  bool get videoReady => _videoReady;

  bool get isPlaying {
    if (isVideo) {
      if (_videoSupported && _mkPlayer != null) return _mkPlayer!.state.playing;
      if (_androidController != null) return _androidController!.value.isPlaying;
      return false;
    }
    return _audio.playing;
  }

  VideoController? get videoController => _mkController;
  VideoPlayerController? get androidVideoController => _androidController;

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

  bool isFavourite(String path) => _favourites.contains(path);

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
        // tab-separated: path \t type \t title \t artist
        list.add('${item.path}\t${item.type == MediaType.video ? 'v' : 'a'}\t${item.title ?? ''}\t${item.artist ?? ''}');
      }
    }
    prefs.setStringList('player_favourites_cache', list);
  }

  List<MapEntry<int, MediaItem>> get favouriteEntries => library
      .asMap()
      .entries
      .where((e) => _favourites.contains(e.value.path))
      .toList();

  // ── Library loading ──

  Future<String> _resolveLocalPath(String path) async {
    if (path.startsWith('content://')) {
      final copied = await PlatformDirs.copyToTemp(path);
      return copied ?? path;
    }
    return path;
  }

  Future<void> setLibrary(List<MediaItem> items) async {
    isLoading = true;
    library = List.from(items);
    currentIndex = 0;
    notifyListeners();

    // ── Process audio metadata in parallel batches for speed ──
    const batchSize = 6;
    for (int start = 0; start < library.length; start += batchSize) {
      final end = start + batchSize > library.length
          ? library.length
          : start + batchSize;
      await Future.wait(
        List.generate(end - start, (j) => _enrichMetadata(start + j)),
      );
      notifyListeners();
    }

    // Mark how many items came from this folder.
    _folderItemCount = library.length;

    // Append cached favourites that are NOT in the current folder so the
    // Favourites tab still shows them.
    final folderPaths = library.map((e) => e.path).toSet();
    for (final path in _favourites) {
      if (!folderPaths.contains(path) && _favouriteCache.containsKey(path)) {
        library.add(_favouriteCache[path]!);
      }
    }

    // Update the favourite cache with fresher metadata from this folder.
    for (int i = 0; i < _folderItemCount; i++) {
      if (_favourites.contains(library[i].path)) {
        _favouriteCache[library[i].path] = library[i];
      }
    }
    _saveFavouriteCache();

    currentIndex = 0;
    isLoading = false;
    notifyListeners();

    // ── Generate video thumbnails lazily in background ──
    for (int i = 0; i < _folderItemCount; i++) {
      if (library[i].type == MediaType.video &&
          library[i].thumbnailData == null) {
        final idx = i;
        final path = library[i].path;
        _generateVideoThumbnail(path).then((thumb) {
          if (thumb != null &&
              idx < library.length &&
              library[idx].path == path) {
            library[idx] = library[idx].copyWith(thumbnailData: thumb);
            notifyListeners();
          }
        });
      }
    }
  }

  /// Read audio metadata + embedded art for a single library item.
  Future<void> _enrichMetadata(int i) async {
    if (i >= library.length) return;
    final item = library[i];
    try {
      final metaPath = await _resolveLocalPath(item.path);
      final tag = await readMetadata(File(metaPath), getImage: true);
      Uint8List? safePng;
      if (tag.pictures.isNotEmpty) {
        for (final pic in tag.pictures) {
          final raw = pic.bytes;
          if (raw.isEmpty) continue;
          safePng = await _transcodeToSafePng(raw, mimeType: pic.mimetype);
          if (safePng != null) break;
        }
      }
      library[i] = item.copyWith(
        title: tag.title?.trim().isNotEmpty == true
            ? tag.title!.trim()
            : item.title,
        artist: tag.artist?.trim().isNotEmpty == true
            ? tag.artist!.trim()
            : item.artist,
        thumbnailData: safePng ?? item.thumbnailData,
      );
    } catch (e) {
      debugPrint('metadata error for ${item.path}: $e');
    }
  }

  Future<Uint8List?> _generateVideoThumbnail(String filePath) async {
    debugPrint('generating thumbnail for $filePath');

    final resolved = await _resolveLocalPath(filePath);

    // Strategy 1: video_thumbnail plugin (fast, native, preferred)
    Uint8List? snap;
    try {
      snap = await VideoThumbnail.thumbnailData(
        video: resolved,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 256,
        quality: 60,
      );
      debugPrint(
          'video_thumbnail returned ${snap?.length ?? 0} bytes for $resolved');
    } catch (e) {
      debugPrint('video_thumbnail error for $resolved: $e');
    }

    if (_isValidImageBytes(snap)) {
      return _transcodeToSafePng(snap!, mimeType: 'image/jpeg');
    }

    // Strategy 2: media_kit screenshot (desktop/iOS only)
    if (_videoSupported && _thumbPlayer != null) {
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
          final seekMs =
              (dur.inMilliseconds * 0.1).round().clamp(0, 15000);
          await _thumbPlayer!.seek(Duration(milliseconds: seekMs));
        }

        await Future.delayed(const Duration(milliseconds: 400));
        snap = await _thumbPlayer!.screenshot();
        debugPrint(
            'screenshot() returned ${snap?.length ?? 0} bytes for $filePath');
      } catch (e) {
        debugPrint('screenshot error for $filePath: $e');
      } finally {
        try {
          await _thumbPlayer!.stop();
        } catch (_) {}
      }
    }

    if (_isValidImageBytes(snap)) {
      final result = await _transcodeToSafePng(snap!);
      if (result != null) return result;

      try {
        if (_videoSupported && _thumbPlayer != null) {
          final w = await _thumbPlayer!.stream.width
              .firstWhere((w) => w != null && w > 0)
              .timeout(const Duration(seconds: 2));
          final h = await _thumbPlayer!.stream.height
              .firstWhere((h) => h != null && h > 0)
              .timeout(const Duration(seconds: 2));

          if (w != null && h != null && snap.length == w * h * 4) {
            final rgba = Uint8List(snap.length);
            for (int i = 0; i < snap.length; i += 4) {
              rgba[i] = snap[i + 2];
              rgba[i + 1] = snap[i + 1];
              rgba[i + 2] = snap[i];
              rgba[i + 3] = snap[i + 3];
            }
            final imgBuf = img.Image.fromBytes(
              width: w,
              height: h,
              bytes: rgba.buffer,
            );
            return Uint8List.fromList(img.encodePng(imgBuf));
          }
        }
      } catch (_) {}
    }

    debugPrint('all thumbnail strategies failed for $filePath');
    return null;
  }

  bool _isValidImageBytes(Uint8List? bytes) =>
      bytes != null && bytes.length >= 64;

  void _applyVolume() {
    _audio.setVolume(volume);
    // Videos are often mastered quieter than music — apply a boost.
    final videoVol = (volume * _videoVolumeBoost).clamp(0.0, 1.0);
    if (_videoSupported && _mkPlayer != null) {
      _mkPlayer!.setVolume(videoVol * 100);
    }
    _androidController?.setVolume(videoVol);
  }

  // ── Playback ──

  Future<void> select(int index) async {
    if (index < 0 || index >= library.length) return;
    currentIndex = index;
    await _loadCurrent();
    notifyListeners();
  }

  /// Remove the listener and dispose the Android controller safely.
  Future<void> _disposeAndroidController() async {
    if (_androidController == null) return;
    if (_androidListener != null) {
      _androidController!.removeListener(_androidListener!);
      _androidListener = null;
    }
    try {
      await _androidController!.dispose();
    } catch (e) {
      debugPrint('android controller dispose error: $e');
    }
    _androidController = null;
  }

  Future<void> _loadCurrent() async {
    if (currentItem == null) return;
    if (_loadingTrack) {
      // Another load is in progress – mark pending so we reload
      // the (now-updated) currentIndex once it finishes.
      _pendingReload = true;
      return;
    }
    final item = currentItem!; // Capture once – library may change across awaits
    _loadingTrack = true;
    _pendingReload = false;
    _videoCompletionFired = false;
    _videoReady = false;
    notifyListeners();

    _applyVolume();

    try {
      if (item.type == MediaType.audio) {
        if (_videoSupported && _mkPlayer != null) {
          await _mkPlayer!.stop();
        }
        await _disposeAndroidController();
        try {
          final path = item.path;
          if (path.startsWith('content://')) {
            await _audio.setUrl(path);
          } else {
            await _audio.setFilePath(path);
          }
          await _audio.setVolume(volume);
          duration = _audio.duration;
          position = Duration.zero;
          await _audio.play();
          _updateMediaNotification();
        } catch (e) {
          debugPrint('audio load error ($item): $e');
        }
      } else {
        await _audio.stop();
        try {
          if (_videoSupported && _mkPlayer != null) {
            // ── Desktop / iOS: media_kit ──
            await _mkPlayer!.open(Media(_toUri(item.path)), play: true);
            final videoVol = (volume * _videoVolumeBoost).clamp(0.0, 1.0);
            await _mkPlayer!.setVolume(videoVol * 100);
          } else {
            // ── Android: video_player (ExoPlayer) ──
            await _disposeAndroidController();

            final path = item.path;
            VideoPlayerController? ctrl;

            // Try 1: content:// URI directly — ExoPlayer handles SAF URIs natively.
            if (path.startsWith('content://')) {
              try {
                ctrl = VideoPlayerController.networkUrl(Uri.parse(path));
                await ctrl.initialize();
              } catch (e) {
                debugPrint('android VP content:// init failed: $e');
                try { await ctrl?.dispose(); } catch (_) {}
                ctrl = null;
              }
            }

            // Try 2: regular file path.
            if (ctrl == null && !path.startsWith('content://')) {
              try {
                ctrl = VideoPlayerController.file(File(path));
                await ctrl.initialize();
              } catch (e) {
                debugPrint('android VP file init failed: $e');
                try { await ctrl?.dispose(); } catch (_) {}
                ctrl = null;
              }
            }

            // Try 3: copy content URI to a temp file, then open as file.
            if (ctrl == null && path.startsWith('content://')) {
              try {
                final local = await _resolveLocalPath(path);
                if (local != path) {
                  ctrl = VideoPlayerController.file(File(local));
                  await ctrl.initialize();
                }
              } catch (e) {
                debugPrint('android VP temp-copy init failed: $e');
                try { await ctrl?.dispose(); } catch (_) {}
                ctrl = null;
              }
            }

            if (ctrl != null) {
              _androidController = ctrl;
              duration = ctrl.value.duration;
              position = Duration.zero;
              final videoVol = (volume * _videoVolumeBoost).clamp(0.0, 1.0);
              await ctrl.setVolume(videoVol);
              await ctrl.play();
              // initialize() completes synchronously once the codec is ready,
              // so the widget can be shown immediately.
              _videoReady = true;

              // Mirror position/duration/completion back into PlayerState so
              // the progress slider and next-track logic work correctly.
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
                notifyListeners();
              }
              _androidListener = listener;
              ctrl.addListener(listener);
            } else {
              debugPrint('all android VP strategies failed for $path');
            }

            position = Duration.zero;
          }
        } catch (e) {
          debugPrint('video load error: $e');
        }
      }
    } finally {
      _loadingTrack = false;
      notifyListeners();
      // If another track was requested while we were busy, load it now.
      if (_pendingReload) {
        _pendingReload = false;
        await _loadCurrent();
      }
    }
  }

  String _toUri(String path) {
    if (path.startsWith('file://') || path.startsWith('http') ||
        path.startsWith('content://')) return path;
    if (Platform.isWindows) return Uri.file(path, windows: true).toString();
    return Uri.file(path).toString();
  }

  void togglePlay() {
    if (isVideo) {
      if (_videoSupported && _mkPlayer != null) {
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
      if (_videoSupported && _mkPlayer != null) {
        _mkPlayer!.seek(d);
      } else if (_androidController != null) {
        _androidController!.seekTo(d);
      }
    } else {
      _audio.seek(d);
    }
    position = d;
    notifyListeners();
  }

  Future<void> next({MediaType? only}) async {
    if (library.isEmpty) return;
    final scope = _folderItemCount > 0 ? _folderItemCount : library.length;
    int start = currentIndex;
    int visited = 0;
    do {
      currentIndex = shuffle
          ? _randomOther(scope)
          : (currentIndex + 1) % scope;
      visited++;
      final item = library[currentIndex];
      if (only != null) {
        if (item.type == only) break;
      } else {
        if (_videoSupported || Platform.isAndroid || item.type == MediaType.audio) break;
      }
    } while (currentIndex != start && visited < scope);
    await _loadCurrent();
    notifyListeners();
  }

  Future<void> previous({MediaType? only}) async {
    if (library.isEmpty) return;
    final scope = _folderItemCount > 0 ? _folderItemCount : library.length;
    int start = currentIndex;
    int visited = 0;
    do {
      currentIndex = shuffle
          ? _randomOther(scope)
          : (currentIndex - 1 + scope) % scope;
      visited++;
      final item = library[currentIndex];
      if (only != null) {
        if (item.type == only) break;
      } else {
        if (_videoSupported || Platform.isAndroid || item.type == MediaType.audio) break;
      }
    } while (currentIndex != start && visited < scope);
    await _loadCurrent();
    notifyListeners();
  }

  int _randomOther(int scope) {
    if (scope <= 1) return 0;
    int idx;
    do {
      idx = _random.nextInt(scope);
    } while (idx == currentIndex);
    return idx;
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
    repeatMode = RepeatMode
        .values[(repeatMode.index + 1) % RepeatMode.values.length];
    prefs.setInt('repeat', repeatMode.index);
    notifyListeners();
  }

  Future<void> _loadPrefs() async {
    volume = prefs.getDouble('volume') ?? 0.5;
    shuffle = prefs.getBool('shuffle') ?? false;
    repeatMode = RepeatMode.values[
        (prefs.getInt('repeat') ?? 0).clamp(0, RepeatMode.values.length - 1)];
    _favourites = (prefs.getStringList('player_favourites') ?? []).toSet();

    // Restore favourite metadata cache.
    _favouriteCache.clear();
    for (final raw in prefs.getStringList('player_favourites_cache') ?? []) {
      final parts = raw.split('\t');
      if (parts.length >= 2) {
        final path = parts[0];
        final type = parts[1] == 'v' ? MediaType.video : MediaType.audio;
        final title = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
        final artist = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
        _favouriteCache[path] = MediaItem(path, type,
            title: title, artist: artist);
      }
    }
    notifyListeners();
  }

  Future<void> _handleCompletion() async {
    if (repeatMode == RepeatMode.one) {
      _videoCompletionFired = false;
      await _loadCurrent();
      return;
    }
    if (repeatMode == RepeatMode.all) {
      await next(only: activeTabFilter);
      return;
    }
    // RepeatMode.off
    final scope = _folderItemCount > 0 ? _folderItemCount : library.length;
    if (shuffle || currentIndex < scope - 1) {
      await next(only: activeTabFilter);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _audio.dispose();
    if (_videoSupported && _mkPlayer != null) {
      _mkPlayer!.dispose();
    }
    if (_videoSupported && _thumbPlayer != null) {
      _thumbPlayer!.dispose();
    }
    _disposeAndroidController();
    super.dispose();
  }
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
  late final ScrollController _allScrollController;
  late final ScrollController _songsScrollController;
  late final ScrollController _videosScrollController;
  late final ScrollController _favouritesScrollController;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const _accent = Color(0xFF4A7EDB);

  Color get _bg => Theme.of(context).scaffoldBackgroundColor;
  Color get _text => Theme.of(context).colorScheme.onSurface;
  Color get _sub =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
  Color get _div => Theme.of(context).dividerColor;
  Color get _tile => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF2C2C2E)
      : const Color(0xFFE0E0E0);

  static Color _a(double a) => _accent.withValues(alpha: a);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _allScrollController = ScrollController();
    _songsScrollController = ScrollController();
    _videosScrollController = ScrollController();
    _favouritesScrollController = ScrollController();

    // Update activeTabFilter on the PlayerState when tabs change.
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final state = context.read<PlayerState>();
      switch (_tabController.index) {
        case 1:
          state.activeTabFilter = MediaType.audio;
          break;
        case 2:
          state.activeTabFilter = MediaType.video;
          break;
        default:
          state.activeTabFilter = null;
          break;
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _allScrollController.dispose();
    _songsScrollController.dispose();
    _videosScrollController.dispose();
    _favouritesScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Filter entries by search query.
  bool _matchesSearch(MediaItem item) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    final title = (item.title ?? p.basenameWithoutExtension(item.path)).toLowerCase();
    final artist = (item.artist ?? '').toLowerCase();
    return title.contains(q) || artist.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();

    return Scaffold(
      body: Column(
        children: [
          // ── Persistent video renderer (always in tree, hidden when not needed) ──
          _PersistentVideoWidget(
            mkController: state.videoController,
            androidController: state.androidVideoController,
            visible: state.isVideo &&
                (state.videoController != null || state.androidVideoController != null),
            ready: state.videoReady,
            onTap: state.togglePlay,
            accent: _accent,
            tileBg: _tile,
          ),

          // ── Scrollable content ──
          Expanded(
            child: CustomScrollView(
              primary: false,
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverToBoxAdapter(child: _nowPlaying(state)),
                if (state.isLoading)
                  SliverToBoxAdapter(
                    child: LinearProgressIndicator(color: _accent),
                  ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabHeaderDelegate(
                    TabBar(
                      controller: _tabController,
                      labelColor: _accent,
                      unselectedLabelColor: _sub,
                      indicatorColor: _accent,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        Tab(text: 'All (${state.folderItemCount})'),
                        Tab(text: '♪ Songs (${state.audioEntries.length})'),
                        Tab(text: '▶ Videos (${state.videoEntries.length})'),
                        Tab(text: '★ Favourites (${state.favouriteEntries.length})'),
                      ],
                    ),
                    bg: _bg,
                  ),
                ),
                // ── Search bar ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search library…',
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
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 12),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    ),
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _allTab(state),
                      _songsTab(state),
                      _videosTab(state),
                      _favouritesTab(state),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _header() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(
          children: [
            const Icon(Icons.music_note, color: _accent, size: 26),
            const SizedBox(width: 8),
            const Text('Lofi Player',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _accent,
                    letterSpacing: -0.5)),
            const Spacer(),
            Builder(
                builder: (ctx) => IconButton(
                      icon: Icon(Icons.folder_open,
                          color: Theme.of(ctx).colorScheme.onSurface),
                      tooltip: 'Open folder',
                      onPressed: _pickFolder,
                    )),
          ],
        ),
      ),
    );
  }

  // ── Now Playing ──────────────────────────────────────────────────────────

  Widget _nowPlaying(PlayerState state) {
    final item = state.currentItem;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          // Art — only shown for audio; video uses the persistent widget above
          if (!state.isVideo)
            item?.thumbnailData != null
                ? Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _img(item!.thumbnailData!, height: 130),
                    ),
                  )
                : SizedBox(
                    height: 90,
                    child: Center(
                      child: Icon(Icons.music_note, size: 72, color: _a(0.25)),
                    ),
                  ),

          const SizedBox(height: 10),

          Text(
            item?.title ??
                (item != null ? p.basenameWithoutExtension(item.path) : '—'),
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: _text),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          if (item?.artist != null) ...[
            const SizedBox(height: 2),
            Text(item!.artist!,
                style: TextStyle(fontSize: 12, color: _sub),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],

          const SizedBox(height: 10),
          _progress(state),
          const SizedBox(height: 4),
          _controls(state),
          const SizedBox(height: 6),
          _volume(state),
          Divider(height: 20, color: _div),
        ],
      ),
    );
  }

  Widget _progress(PlayerState state) {
    final pos = state.position;
    final dur = state.duration ?? Duration.zero;
    final maxMs = dur.inMilliseconds.toDouble();
    final val =
        pos.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    return Column(children: [
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          activeTrackColor: _accent,
          inactiveTrackColor: _a(0.2),
          thumbColor: _accent,
          overlayColor: _a(0.15),
        ),
        child: Slider(
          value: val,
          max: maxMs > 0 ? maxMs : 1.0,
          onChanged: (v) => state.seek(Duration(milliseconds: v.round())),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_fmt(pos), style: TextStyle(fontSize: 11, color: _sub)),
            Text(_fmt(dur), style: TextStyle(fontSize: 11, color: _sub)),
          ],
        ),
      ),
    ]);
  }

  Widget _controls(PlayerState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _toggleBtn(
          icon: state.shuffle ? Icons.shuffle_on : Icons.shuffle,
          label: state.shuffle ? 'On' : 'Off',
          active: state.shuffle,
          onTap: state.toggleShuffle,
        ),
        const SizedBox(width: 8),
        _iconBtn(
          Icons.skip_previous_rounded,
          () {
            state.previous(only: state.activeTabFilter);
          },
          size: 30,
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: state.library.isEmpty ? null : state.togglePlay,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: state.library.isEmpty ? _sub : _text,
              shape: BoxShape.circle,
            ),
            child: Icon(
              state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: _bg,
              size: 30,
            ),
          ),
        ),
        const SizedBox(width: 6),
        _iconBtn(
          Icons.skip_next_rounded,
          () {
            state.next(only: state.activeTabFilter);
          },
          size: 30,
        ),
        const SizedBox(width: 8),
        _toggleBtn(
          icon: state.repeatMode == RepeatMode.one
              ? Icons.repeat_one
              : Icons.repeat,
          label: switch (state.repeatMode) {
            RepeatMode.off => 'Off',
            RepeatMode.one => 'One',
            RepeatMode.all => 'All',
          },
          active: state.repeatMode != RepeatMode.off,
          onTap: state.cycleRepeat,
        ),
        const SizedBox(width: 8),
        _iconBtn(
          Icons.cast,
          state.currentItem == null
              ? () {}
              : () {
                  CastDialog.show(
                    context: context,
                    filePath: state.currentItem!.path,
                    title: state.currentItem!.title ?? 'Media',
                  );
                },
          size: 22,
        ),
      ],
    );
  }

  Widget _volume(PlayerState state) {
    return Row(children: [
      Icon(Icons.volume_down, size: 18, color: _sub),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            activeTrackColor: _accent,
            inactiveTrackColor: _a(0.2),
            thumbColor: _accent,
          ),
          child: Slider(value: state.volume, onChanged: state.setVolume),
        ),
      ),
      Icon(Icons.volume_up, size: 18, color: _sub),
      const SizedBox(width: 6),
      SizedBox(
        width: 36,
        child: Text('${(state.volume * 100).round()}%',
            style: TextStyle(fontSize: 11, color: _sub),
            textAlign: TextAlign.right),
      ),
    ]);
  }

  Widget _toggleBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color = active ? _accent : _sub;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 20),
          Text(label, style: TextStyle(fontSize: 9, color: color)),
        ]),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {double size = 26}) {
    return InkWell(
      borderRadius: BorderRadius.circular(size),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: size, color: _text),
      ),
    );
  }

  // ── Tab views ────────────────────────────────────────────────────────────

  Widget _allTab(PlayerState state) {
    if (state.library.isEmpty) return _empty();
    final filteredAudio = state.audioEntries
        .where((e) => _matchesSearch(e.value))
        .toList();
    final filteredVideo = state.videoEntries
        .where((e) => _matchesSearch(e.value))
        .toList();
    if (filteredAudio.isEmpty && filteredVideo.isEmpty) return _noResults();
    return Scrollbar(
      controller: _allScrollController,
      child: ListView(
        controller: _allScrollController,
        primary: false,
        children: [
          if (filteredAudio.isNotEmpty) ...[
            _sectionHeader('♪ Songs'),
            ...filteredAudio.map((e) => _songTile(state, e.key, e.value)),
          ],
          if (filteredVideo.isNotEmpty) ...[
            _sectionHeader('▶ Videos'),
            _videoGrid(state, filteredVideo),
          ],
        ],
      ),
    );
  }

  Widget _songsTab(PlayerState state) {
    if (state.audioEntries.isEmpty) return _empty();
    final filtered = state.audioEntries
        .where((e) => _matchesSearch(e.value))
        .toList();
    if (filtered.isEmpty) return _noResults();
    return Scrollbar(
      controller: _songsScrollController,
      child: ListView.builder(
        controller: _songsScrollController,
        primary: false,
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final e = filtered[i];
          return _songTile(state, e.key, e.value);
        },
      ),
    );
  }

  Widget _videosTab(PlayerState state) {
    if (state.videoEntries.isEmpty) return _empty();
    final filtered = state.videoEntries
        .where((e) => _matchesSearch(e.value))
        .toList();
    if (filtered.isEmpty) return _noResults();
    return Scrollbar(
      controller: _videosScrollController,
      child: ListView(
        controller: _videosScrollController,
        primary: false,
        children: [_videoGrid(state, filtered)],
      ),
    );
  }

  Widget _favouritesTab(PlayerState state) {
    final favs = state.favouriteEntries
        .where((e) => _matchesSearch(e.value))
        .toList();
    if (favs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border,
                size: 64, color: _sub.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('No favourites yet',
                style: TextStyle(color: _sub, fontSize: 14)),
            const SizedBox(height: 4),
            Text('Tap the heart icon on any track',
                style: TextStyle(color: _sub.withValues(alpha: 0.6),
                    fontSize: 12)),
          ],
        ),
      );
    }
    final favAudio = favs.where((e) => e.value.type == MediaType.audio).toList();
    final favVideo = favs.where((e) => e.value.type == MediaType.video).toList();
    return Scrollbar(
      controller: _favouritesScrollController,
      child: ListView(
        controller: _favouritesScrollController,
        primary: false,
        children: [
          if (favAudio.isNotEmpty) ...[
            _sectionHeader('♪ Songs'),
            ...favAudio.map((e) => _songTile(state, e.key, e.value)),
          ],
          if (favVideo.isNotEmpty) ...[
            _sectionHeader('▶ Videos'),
            _videoGrid(state, favVideo),
          ],
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open,
              size: 64, color: _sub.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('Open a folder to load media',
              style: TextStyle(color: _sub, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _noResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off,
              size: 64, color: _sub.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('No matches found',
              style: TextStyle(color: _sub, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _accent,
              letterSpacing: 0.8)),
    );
  }

  Widget _songTile(PlayerState state, int index, MediaItem item) {
    final sel = index == state.currentIndex;
    final isFav = state.isFavourite(item.path);
    return Material(
      color: sel ? _a(0.1) : Colors.transparent,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: _thumb(item, 46, Icons.audiotrack),
        title: Text(
          item.title ?? p.basenameWithoutExtension(item.path),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              color: sel ? _accent : _text),
        ),
        subtitle: item.artist != null
            ? Text(item.artist!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: _sub))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => state.toggleFavourite(item.path),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                  color: isFav ? Colors.redAccent : _sub,
                ),
              ),
            ),
            if (sel)
              const Icon(Icons.equalizer, color: _accent, size: 18),
          ],
        ),
        onTap: () => state.select(index),
      ),
    );
  }

  Widget _videoGrid(
      PlayerState state, List<MapEntry<int, MediaItem>> entries) {
    return GridView.builder(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 16 / 9,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final idx = entries[i].key;
        final item = entries[i].value;
        final sel = idx == state.currentIndex;
        final isFav = state.isFavourite(item.path);

        return GestureDetector(
          onTap: () => state.select(idx),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(fit: StackFit.expand, children: [
                    item.thumbnailData != null
                        ? _img(item.thumbnailData!, fit: BoxFit.cover)
                        : Container(
                            color: _tile,
                            child:
                                Icon(Icons.videocam, color: _sub, size: 32)),
                    if (sel) Container(color: _a(0.3)),
                    Center(
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          sel
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => state.toggleFavourite(item.path),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isFav ? Icons.favorite : Icons.favorite_border,
                            size: 14,
                            color: isFav ? Colors.redAccent : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.title ?? p.basenameWithoutExtension(item.path),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.artist != null)
                Text(item.artist!,
                    style: TextStyle(fontSize: 10, color: _sub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      },
    );
  }

  // ── Image helpers ─────────────────────────────────────────────────────────

  Widget _thumb(MediaItem item, double size, IconData fallback) {
    if (item.thumbnailData != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: _img(item.thumbnailData!,
            width: size, height: size, fit: BoxFit.cover),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: _tile, borderRadius: BorderRadius.circular(4)),
      child: Icon(fallback, color: _sub, size: size * 0.5),
    );
  }

  Widget _img(Uint8List bytes,
      {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    return Image.memory(bytes,
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true, errorBuilder: (_, e, __) {
      debugPrint('image render error: $e');
      return Container(
          width: width,
          height: height,
          color: _tile,
          child: Icon(Icons.broken_image, color: _sub, size: 24));
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _pickFolder() async {
    String? result;
    if (!kIsWeb && Platform.isAndroid) {
      result = await PlatformDirs.pickTree();
      debugPrint('SAF pickTree returned: $result');
    }
    result ??= await FilePicker.platform.getDirectoryPath();
    debugPrint('picked folder path: $result');
    if (result == null || !mounted) return;

    const audioExt = ['.mp3', '.wav', '.m4a', '.flac', '.aac', '.ogg', '.opus'];
    const videoExt = ['.mp4', '.mov', '.mkv', '.avi', '.webm', '.flv', '.wmv'];

    List<MediaItem> files = [];

    try {
      if (result.startsWith('content://')) {
        final entries = await PlatformDirs.listTree(result);
        debugPrint('listTree returned ${entries.length} entries');
        for (final entry in entries) {
          final uri = entry['uri'] ?? '';
          if (uri.isEmpty) continue;
          final name = entry['name'] ?? '';
          final mime = entry['mime'] ?? '';
          var ext = p.extension(name).toLowerCase();
          debugPrint('SAF entry uri=$uri name=$name mime=$mime ext=$ext');
          if (ext.isEmpty && mime.isNotEmpty) {
            if (mime.contains('/')) {
              final subtype = mime.split('/').last;
              ext = '.$subtype';
            }
          }
          if (!audioExt.contains(ext) && !videoExt.contains(ext)) continue;
          final type = videoExt.contains(ext) ? MediaType.video : MediaType.audio;
          files.add(MediaItem(uri, type,
              title: p.basenameWithoutExtension(name)));
        }
      } else {
        final dir = Directory(result);
        if (await dir.exists()) {
          files = dir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) {
                final ext = p.extension(f.path).toLowerCase();
                return audioExt.contains(ext) || videoExt.contains(ext);
              })
              .map((f) {
                final ext = p.extension(f.path).toLowerCase();
                final type =
                    videoExt.contains(ext) ? MediaType.video : MediaType.audio;
                return MediaItem(f.path, type,
                    title: p.basenameWithoutExtension(f.path));
              })
              .toList();
        } else {
          final picked = await FilePicker.platform.pickFiles(
            allowMultiple: true,
            type: FileType.custom,
            allowedExtensions: [...audioExt, ...videoExt]
                .map((e) => e.substring(1))
                .toList(),
          );
          if (picked != null && picked.files.isNotEmpty) {
            for (final pf in picked.files) {
              final path = pf.path;
              if (path == null) continue;
              final ext = p.extension(path).toLowerCase();
              final type =
                  videoExt.contains(ext) ? MediaType.video : MediaType.audio;
              files.add(MediaItem(path, type,
                  title: p.basenameWithoutExtension(path)));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('folder scan failed, falling back to file picker: $e');
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [...audioExt, ...videoExt]
            .map((e) => e.substring(1))
            .toList(),
      );
      if (picked != null && picked.files.isNotEmpty) {
        for (final pf in picked.files) {
          final path = pf.path;
          if (path == null) continue;
          final ext = p.extension(path).toLowerCase();
          final type =
              videoExt.contains(ext) ? MediaType.video : MediaType.audio;
          files.add(MediaItem(path, type,
              title: p.basenameWithoutExtension(path)));
        }
      }
    }

    if (mounted) context.read<PlayerState>().setLibrary(files);
  }
}

// ─── Persistent video widget ──────────────────────────────────────────────────

class _PersistentVideoWidget extends StatefulWidget {
  final VideoController? mkController;
  final VideoPlayerController? androidController;
  final bool visible;
  final bool ready;
  final VoidCallback onTap;
  final Color accent;
  final Color tileBg;

  const _PersistentVideoWidget({
    this.mkController,
    this.androidController,
    required this.visible,
    required this.ready,
    required this.onTap,
    required this.accent,
    required this.tileBg,
  });

  @override
  State<_PersistentVideoWidget> createState() => _PersistentVideoWidgetState();
}

class _PersistentVideoWidgetState extends State<_PersistentVideoWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!widget.visible) return const SizedBox.shrink();

    return LayoutBuilder(builder: (ctx, bc) {
      final screenH = MediaQuery.of(ctx).size.height;
      final maxH = screenH * 0.35;
      final targetH = bc.maxWidth * 9 / 16;
      final height = targetH.clamp(0.0, maxH);

      return SizedBox(
        height: height,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Stack(fit: StackFit.expand, children: [
            if (widget.androidController != null)
              // ValueListenableBuilder ensures the widget rebuilds when
              // isInitialized / aspectRatio becomes available.
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: widget.androidController!,
                builder: (_, value, __) {
                  if (!value.isInitialized) return Container(color: widget.tileBg);
                  return ClipRect(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
                        child: VideoPlayer(widget.androidController!),
                      ),
                    ),
                  );
                },
              )
            else if (widget.mkController != null)
              ClipRect(child: Video(controller: widget.mkController!)),
            if (!widget.ready)
              Container(
                color: widget.tileBg,
                child: Center(
                  child: CircularProgressIndicator(color: widget.accent),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

// ─── Tab bar sliver delegate ──────────────────────────────────────────────────

class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color bg;
  const _TabHeaderDelegate(this.tabBar, {required this.bg});

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: bg, child: tabBar);

  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  bool shouldRebuild(_TabHeaderDelegate old) => old.bg != bg;
}