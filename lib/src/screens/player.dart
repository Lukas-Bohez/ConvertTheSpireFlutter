import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
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
import 'package:visibility_detector/visibility_detector.dart';
import '../services/platform_dirs.dart';
import '../services/audio_handler.dart';

// ─────────────────────────────────────────────────────────────────────────────
// IMPORTANT: In your main.dart add these two lines before runApp():
//   WidgetsFlutterBinding.ensureInitialized();
//   MediaKit.ensureInitialized();
// ─────────────────────────────────────────────────────────────────────────────

// ─── Wrapper ──────────────────────────────────────────────────────────────────

/// Public entry point used by HomeScreen (case-correct name).
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlayerScreen();
  }
}

// ─── Data types ───────────────────────────────────────────────────────────────

enum MediaType { audio, video }

enum RepeatMode { off, one, all }

/// Determines which subset of the library is used for playback.
enum PlaybackMode { all, songs, videos, favourites }

class MediaItem {
  final String path;
  final MediaType type;
  final String? title;
  final String? artist;
  // Always PNG-encoded after processing — safe for Image.memory everywhere.
  final Uint8List? thumbnailData;
  final Duration? duration;

  const MediaItem(this.path, this.type,
      {this.title, this.artist, this.thumbnailData, this.duration});

  MediaItem copyWith(
          {String? title,
          String? artist,
          Uint8List? thumbnailData,
          Duration? duration}) =>
      MediaItem(path, type,
          title: title ?? this.title,
          artist: artist ?? this.artist,
          thumbnailData: thumbnailData ?? this.thumbnailData,
          duration: duration ?? this.duration);
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

    decoded ??= _decodeByMagic(raw);
    decoded ??= img.decodeImage(raw);

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
  if (raw[0] == 0x89 && raw[1] == 0x50 && raw[2] == 0x4E && raw[3] == 0x47) {
    return img.decodePng(raw);
  }
  if (raw[0] == 0x47 && raw[1] == 0x49 && raw[2] == 0x46 && raw[3] == 0x38) {
    return img.decodeGif(raw);
  }
  if (raw[0] == 0x42 && raw[1] == 0x4D) {
    return img.decodeBmp(raw);
  }
  if (raw.length >= 12 &&
      raw[0] == 0x52 &&
      raw[1] == 0x49 &&
      raw[2] == 0x46 &&
      raw[3] == 0x46 &&
      raw[8] == 0x57 &&
      raw[9] == 0x45 &&
      raw[10] == 0x42 &&
      raw[11] == 0x50) {
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
  MediaType? activeTabFilter;

  /// Whether playback is restricted to favourite items only.
  bool favouritesOnly = false;

  /// The user-selected playback mode (persisted & shown in Queue tab).
  PlaybackMode playbackMode = PlaybackMode.all;

  /// Manual queue: indices of library items queued to play next.
  final List<int> manualQueue = [];

  bool get isActuallyPlaying => isPlaying;

  Directory? _thumbCacheDir;

  Set<String> _favourites = {};
  Map<String, MediaItem> _favouriteCache = {};

  int _folderItemCount = 0;
  int _loadVersion = 0;

  int get folderItemCount => _folderItemCount;

  static const double _videoVolumeBoost = 1.8;

  final AudioPlayer _audio = AudioPlayer();

  AppAudioHandler? _audioHandler;

  // media_kit is used on Windows/Linux/macOS/iOS.
  // On Android we use video_player (ExoPlayer) instead.
  final bool _videoSupported = kIsWeb || !Platform.isAndroid;

  Player? _mkPlayer;
  VideoController? _mkController;

  VideoPlayerController? _androidController;
  VoidCallback? _androidListener;

  Player? _thumbPlayer;
  // ignore: unused_field
  VideoController? _thumbVideoCtl;

  bool _videoReady = false;
  bool _videoCompletionFired = false;
  bool _loadingTrack = false;
  bool _pendingReload = false;
  bool _disposed = false;
  final List<StreamSubscription> _subs = [];
  StreamSubscription? _dirWatcher;
  String? _watchedDirPath;

  Duration position = Duration.zero;
  Duration? duration;

  final _random = Random();

  PlayerState(this.prefs) {
    if (_videoSupported) {
      try {
        _mkPlayer = Player();
        _mkController = VideoController(_mkPlayer!);
        _thumbPlayer = Player();
        _thumbVideoCtl = VideoController(_thumbPlayer!);
      } catch (e, st) {
        debugPrint('media_kit player creation failed: $e\n$st');
        _videoReady = false;
        _mkPlayer = null;
        _mkController = null;
        _thumbPlayer = null;
        _thumbVideoCtl = null;
      }
    } else {
      debugPrint('media_kit disabled on Android — using video_player fallback');
    }

    _loadPrefs().then((_) => _applyVolume());

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
      _audioHandler!.onSkipToNext = () => next(only: MediaType.audio);
      _audioHandler!.onSkipToPrevious = () => previous(only: MediaType.audio);
    }
  }

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
        list.add(
            '${item.path}\t${item.type == MediaType.video ? 'v' : 'a'}\t${item.title ?? ''}\t${item.artist ?? ''}');
        if (item.thumbnailData != null) {
          _saveThumbToCache(path, item.thumbnailData!);
        }
      }
    }
    prefs.setStringList('player_favourites_cache', list);
  }

  Future<Directory> _getThumbCacheDir() async {
    if (_thumbCacheDir != null) return _thumbCacheDir!;
    final appDir = await getApplicationSupportDirectory();
    _thumbCacheDir =
        Directory('${appDir.path}${Platform.pathSeparator}thumb_cache');
    if (!_thumbCacheDir!.existsSync()) {
      _thumbCacheDir!.createSync(recursive: true);
    }
    return _thumbCacheDir!;
  }

  String _thumbCacheKey(String path) {
    final hash = path.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    return hash;
  }

  Future<void> _saveThumbToCache(String itemPath, Uint8List data) async {
    try {
      final dir = await _getThumbCacheDir();
      final file = File(
          '${dir.path}${Platform.pathSeparator}${_thumbCacheKey(itemPath)}.png');
      await file.writeAsBytes(data);
    } catch (e) {
      debugPrint('thumb cache write error: $e');
    }
  }

  Future<Uint8List?> _loadThumbFromCache(String itemPath) async {
    try {
      final dir = await _getThumbCacheDir();
      final file = File(
          '${dir.path}${Platform.pathSeparator}${_thumbCacheKey(itemPath)}.png');
      if (await file.exists()) return await file.readAsBytes();
    } catch (e) {
      debugPrint('thumb cache read error: $e');
    }
    return null;
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
    final version = ++_loadVersion;
    isLoading = true;
    _folderItemCount = 0;

    try {
      await _audio.stop();
    } catch (_) {}
    if (_videoSupported && _mkPlayer != null) {
      try {
        await _mkPlayer!.stop();
      } catch (_) {}
    }
    await _disposeAndroidController();

    library = List.from(items);
    currentIndex = 0;
    position = Duration.zero;
    duration = null;
    notifyListeners();

    // ── Fast pass: read title & artist only (no images) ──
    final lib = library;
    const batchSize = 20;
    for (int start = 0; start < lib.length; start += batchSize) {
      if (_loadVersion != version) return;
      final end = (start + batchSize).clamp(0, lib.length);
      await Future.wait(
        List.generate(end - start, (j) => _enrichMetadataFast(start + j, lib)),
      );
      if (_loadVersion != version) return;
      notifyListeners();
    }

    _folderItemCount = lib.length;

    // Append cached favourites that are NOT in the current folder.
    final folderPaths = lib.map((e) => e.path).toSet();
    for (final path in _favourites) {
      if (!folderPaths.contains(path) && _favouriteCache.containsKey(path)) {
        library.add(_favouriteCache[path]!);
      }
    }

    // Update the favourite cache with fresher metadata from this folder.
    for (int i = 0; i < _folderItemCount; i++) {
      if (_favourites.contains(lib[i].path)) {
        _favouriteCache[lib[i].path] = lib[i];
      }
    }
    _saveFavouriteCache();

    currentIndex = 0;
    isLoading = false;
    notifyListeners();

    _loadAudioThumbnailsInBackground(version);
    _generateThumbnailsInBackground(version);
    _startDirectoryWatcher(items);
  }

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
      _dirWatcher = dir.watch().listen((event) {
        if (_disposed) return;
        final ext = p.extension(event.path).toLowerCase();
        if (!_mediaExtensions.contains(ext)) return;
        if (!_pendingReload) {
          _pendingReload = true;
          Future.delayed(const Duration(seconds: 2), () {
            if (_disposed) return;
            _pendingReload = false;
            _refreshLibraryFromDisk();
          });
        }
      });
    } catch (e) {
      debugPrint('Directory watcher error: $e');
    }
  }

  static const _mediaExtensions = {
    '.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.aac', '.wma',
    '.mp4', '.mkv', '.avi', '.webm', '.mov', '.wmv', '.flv', '.m4v',
  };

  Future<void> _refreshLibraryFromDisk() async {
    final dirPath = _watchedDirPath;
    if (dirPath == null) return;
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    final files = dir.listSync(recursive: true).whereType<File>().where((f) {
      final ext = p.extension(f.path).toLowerCase();
      return _mediaExtensions.contains(ext);
    }).map((f) {
      final ext = p.extension(f.path).toLowerCase();
      final type = {
        '.mp4', '.mkv', '.avi', '.webm', '.mov', '.wmv', '.flv', '.m4v'
      }.contains(ext)
          ? MediaType.video
          : MediaType.audio;
      return MediaItem(f.path, type, title: p.basenameWithoutExtension(f.path));
    }).toList();

    final currentPaths =
        library.take(_folderItemCount).map((e) => e.path).toSet();
    final newPaths = files.map((e) => e.path).toSet();
    if (currentPaths.length == newPaths.length &&
        currentPaths.containsAll(newPaths)) {
      return;
    }

    await setLibrary(files);
  }

  Future<void> _generateThumbnailsInBackground(int version) async {
    for (int i = 0; i < library.length; i++) {
      if (_loadVersion != version || i >= library.length) return;
      if (library[i].type != MediaType.video ||
          library[i].thumbnailData != null) {
        continue;
      }
      final path = library[i].path;
      if (!path.startsWith('content://')) {
        try {
          if (!await File(path).exists()) continue;
        } catch (_) {
          continue;
        }
      }

      Uint8List? thumb;
      Duration? dur;

      try {
        final metaPath = await _resolveLocalPath(path);
        final tag = await readMetadata(File(metaPath), getImage: true);
        dur = tag.duration;
        if (tag.pictures.isNotEmpty) {
          for (final pic in tag.pictures) {
            if (pic.bytes.isEmpty) continue;
            thumb =
                await _transcodeToSafePng(pic.bytes, mimeType: pic.mimetype);
            if (thumb != null) {
              if (kDebugMode) {
                debugPrint(
                    'video embedded art found for $path (${pic.bytes.length} bytes)');
              }
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('video metadata read error for $path: $e');
      }

      thumb ??= await _generateVideoThumbnail(path);

      if (_loadVersion != version) return;
      if (i < library.length && library[i].path == path) {
        if (thumb != null || dur != null) {
          library[i] = library[i].copyWith(
            thumbnailData: thumb ?? library[i].thumbnailData,
            duration: dur,
          );
          if (_favourites.contains(path)) {
            _favouriteCache[path] = library[i];
          }
          notifyListeners();
        }
      }
    }
  }

  Future<void> requestThumbnailForIndex(int index) async {
    if (_disposed) return;
    if (index < 0 || index >= library.length) return;
    final item = library[index];
    if (item.thumbnailData != null) return;

    final path = item.path;
    Uint8List? thumb;
    Duration? dur;

    try {
      final metaPath = await _resolveLocalPath(path);
      final tag = await readMetadata(File(metaPath), getImage: true);
      dur = tag.duration;
      if (tag.pictures.isNotEmpty) {
        for (final pic in tag.pictures) {
          if (pic.bytes.isEmpty) continue;
          thumb = await _transcodeToSafePng(pic.bytes, mimeType: pic.mimetype);
          if (thumb != null) break;
        }
      }
    } catch (e) {
      debugPrint('requestThumbnailForIndex metadata read error for $path: $e');
    }

    if (thumb == null && item.type == MediaType.video) {
      thumb = await _generateVideoThumbnail(path);
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
        if (thumb != null) {
          try {
            await _saveThumbToCache(path, thumb);
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _enrichMetadataFast(int i, List<MediaItem> lib) async {
    if (i >= lib.length) return;
    final item = lib[i];
    try {
      final metaPath = await _resolveLocalPath(item.path);
      final tag = await readMetadata(File(metaPath), getImage: false);
      lib[i] = item.copyWith(
        title: tag.title?.trim().isNotEmpty == true
            ? tag.title!.trim()
            : item.title,
        artist: tag.artist?.trim().isNotEmpty == true
            ? tag.artist!.trim()
            : item.artist,
      );
    } catch (e) {
      debugPrint('metadata fast error for ${item.path}: $e');
    }
  }

  Future<void> _loadAudioThumbnailsInBackground(int version) async {
    for (int i = 0; i < library.length; i++) {
      if (_loadVersion != version || i >= library.length) return;
      if (library[i].type != MediaType.audio) continue;
      if (library[i].thumbnailData != null) continue;
      final path = library[i].path;
      if (!path.startsWith('content://')) {
        try {
          if (!await File(path).exists()) continue;
        } catch (_) {
          continue;
        }
      }
      try {
        final metaPath = await _resolveLocalPath(path);
        final tag = await readMetadata(File(metaPath), getImage: true);
        if (_loadVersion != version || i >= library.length) return;
        if (tag.pictures.isNotEmpty) {
          for (final pic in tag.pictures) {
            if (pic.bytes.isEmpty) continue;
            final safePng =
                await _transcodeToSafePng(pic.bytes, mimeType: pic.mimetype);
            if (_loadVersion != version || i >= library.length) return;
            if (safePng != null) {
              library[i] = library[i].copyWith(thumbnailData: safePng);
              if (_favourites.contains(path)) {
                _favouriteCache[path] = library[i];
              }
              notifyListeners();
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('thumbnail bg error for $path: $e');
      }
    }
  }

  Future<Uint8List?> _generateVideoThumbnail(String filePath) async {
    if (kDebugMode) debugPrint('generating thumbnail for $filePath');

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
          final seekMs = (dur.inMilliseconds * 0.1).round().clamp(0, 15000);
          await _thumbPlayer!.seek(Duration(milliseconds: seekMs));
        }

        await Future.delayed(const Duration(milliseconds: 800));
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

    if (kDebugMode) debugPrint('all thumbnail strategies failed for $filePath');
    return null;
  }

  bool _isValidImageBytes(Uint8List? bytes) =>
      bytes != null && bytes.length >= 64;

  void _applyVolume() {
    _audio.setVolume(volume);
    if (currentItem?.type == MediaType.video) {
      if (_videoSupported && _mkPlayer != null) {
        _mkPlayer!.setVolume(volume * _videoVolumeBoost * 100);
      }
      _androidController
          ?.setVolume((volume * _videoVolumeBoost).clamp(0.0, 1.0));
    }
  }

  // ── Playback ──

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
          if (!_videoSupported &&
              !Platform.isAndroid &&
              e.value.type != MediaType.audio) return false;
          return true;
        })
        .map((e) => e.key)
        .toList();
  }

  Future<void> select(int index) async {
    if (index < 0 || index >= library.length) return;
    currentIndex = index;
    await _loadCurrent();
    notifyListeners();
  }

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
      _pendingReload = true;
      return;
    }
    final item = currentItem!;
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
            await _mkPlayer!.open(Media(_toUri(item.path)), play: true);
            await _mkPlayer!.setVolume(volume * _videoVolumeBoost * 100);
          } else {
            await _disposeAndroidController();

            final path = item.path;
            VideoPlayerController? ctrl;

            if (path.startsWith('content://')) {
              try {
                ctrl = VideoPlayerController.networkUrl(Uri.parse(path));
                await ctrl.initialize();
              } catch (e) {
                debugPrint('android VP content:// init failed: $e');
                try {
                  await ctrl?.dispose();
                } catch (_) {}
                ctrl = null;
              }
            }

            if (ctrl == null && !path.startsWith('content://')) {
              try {
                ctrl = VideoPlayerController.file(File(path));
                await ctrl.initialize();
              } catch (e) {
                debugPrint('android VP file init failed: $e');
                try {
                  await ctrl?.dispose();
                } catch (_) {}
                ctrl = null;
              }
            }

            if (ctrl == null && path.startsWith('content://')) {
              try {
                final local = await _resolveLocalPath(path);
                if (local != path) {
                  ctrl = VideoPlayerController.file(File(local));
                  await ctrl.initialize();
                }
              } catch (e) {
                debugPrint('android VP temp-copy init failed: $e');
                try {
                  await ctrl?.dispose();
                } catch (_) {}
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
                notifyListeners();
              }

              _androidListener = listener;
              ctrl.addListener(listener);
            } else {
              debugPrint('all android VP strategies failed for $path');
              _videoReady = true;
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
      if (_pendingReload) {
        _pendingReload = false;
        await _loadCurrent();
      }
    }
  }

  String _toUri(String path) {
    if (path.startsWith('file://') ||
        path.startsWith('http') ||
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
    final candidates = _getPlaybackCandidates(only: only);
    if (candidates.isEmpty) return;

    if (shuffle) {
      final others = candidates.where((i) => i != currentIndex).toList();
      currentIndex = others.isEmpty
          ? candidates.first
          : others[_random.nextInt(others.length)];
    } else {
      final pos = candidates.indexOf(currentIndex);
      currentIndex = pos >= 0
          ? candidates[(pos + 1) % candidates.length]
          : candidates.first;
    }
    await _loadCurrent();
    notifyListeners();
  }

  Future<void> previous({MediaType? only}) async {
    if (library.isEmpty) return;
    final candidates = _getPlaybackCandidates(only: only);
    if (candidates.isEmpty) return;

    if (shuffle) {
      final others = candidates.where((i) => i != currentIndex).toList();
      currentIndex = others.isEmpty
          ? candidates.first
          : others[_random.nextInt(others.length)];
    } else {
      final pos = candidates.indexOf(currentIndex);
      currentIndex = pos >= 0
          ? candidates[(pos - 1 + candidates.length) % candidates.length]
          : candidates.last;
    }
    await _loadCurrent();
    notifyListeners();
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
    repeatMode =
        RepeatMode.values[(repeatMode.index + 1) % RepeatMode.values.length];
    prefs.setInt('repeat', repeatMode.index);
    notifyListeners();
  }

  Future<void> _loadPrefs() async {
    volume = prefs.getDouble('volume') ?? 0.5;
    shuffle = prefs.getBool('shuffle') ?? false;
    repeatMode = RepeatMode.values[
        (prefs.getInt('repeat') ?? 0).clamp(0, RepeatMode.values.length - 1)];
    playbackMode = PlaybackMode.values[(prefs.getInt('playbackMode') ?? 0)
        .clamp(0, PlaybackMode.values.length - 1)];
    _applyPlaybackMode();
    _favourites = (prefs.getStringList('player_favourites') ?? []).toSet();

    _favouriteCache.clear();
    for (final raw in prefs.getStringList('player_favourites_cache') ?? []) {
      final parts = raw.split('\t');
      if (parts.length >= 2) {
        final path = parts[0];
        final type = parts[1] == 'v' ? MediaType.video : MediaType.audio;
        final title = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
        final artist =
            parts.length > 3 && parts[3].isNotEmpty ? parts[3] : null;
        _favouriteCache[path] =
            MediaItem(path, type, title: title, artist: artist);
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

  void setPlaybackMode(PlaybackMode mode) {
    playbackMode = mode;
    prefs.setInt('playbackMode', mode.index);
    _applyPlaybackMode();
    notifyListeners();
  }

  // ── Queue management ──

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
    if (newIndex < 0) newIndex = 0;
    if (newIndex > manualQueue.length) newIndex = manualQueue.length;
    final item = manualQueue.removeAt(oldIndex);
    if (newIndex > oldIndex) newIndex--;
    manualQueue.insert(newIndex, item);
    notifyListeners();
  }

  void clearQueue() {
    manualQueue.clear();
    notifyListeners();
  }

  Future<void> _handleCompletion() async {
    if (manualQueue.isNotEmpty) {
      currentIndex = manualQueue.removeAt(0);
      await _loadCurrent();
      notifyListeners();
      return;
    }
    if (repeatMode == RepeatMode.one) {
      _videoCompletionFired = false;
      await _loadCurrent();
      return;
    }
    if (repeatMode == RepeatMode.all) {
      await next(only: activeTabFilter);
      return;
    }
    final candidates = _getPlaybackCandidates(only: activeTabFilter);
    final pos = candidates.indexOf(currentIndex);
    if (shuffle || (pos >= 0 && pos < candidates.length - 1)) {
      await next(only: activeTabFilter);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _dirWatcher?.cancel();
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

// ─── Helper for virtualised All / Favourites tabs ─────────────────────────────

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

// ─── Sliver pinned tab bar delegate ──────────────────────────────────────────

class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color bg;

  const _TabHeaderDelegate(this.tabBar, {required this.bg});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(color: bg, child: tabBar);
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(_TabHeaderDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar || bg != oldDelegate.bg;
}

// ─── Persistent video widget ─────────────────────────────────────────────────

class _PersistentVideoWidget extends StatelessWidget {
  final VideoController? mkController;
  final VideoPlayerController? androidController;
  final bool visible;
  final bool ready;
  final VoidCallback onTap;
  final Color accent;
  final Color tileBg;

  const _PersistentVideoWidget({
    required this.mkController,
    required this.androidController,
    required this.visible,
    required this.ready,
    required this.onTap,
    required this.accent,
    required this.tileBg,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    Widget videoChild;
    if (mkController != null) {
      videoChild = Video(controller: mkController!);
    } else if (androidController != null) {
      videoChild = ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: androidController!,
        builder: (_, val, __) {
          if (!val.isInitialized) {
            return Center(
                child: CircularProgressIndicator(color: accent));
          }
          return AspectRatio(
            aspectRatio: val.aspectRatio,
            child: VideoPlayer(androidController!),
          );
        },
      );
    } else {
      videoChild = Center(child: CircularProgressIndicator(color: accent));
    }

    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: ready
              ? videoChild
              : Center(child: CircularProgressIndicator(color: accent)),
        ),
      ),
    );
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
  late final ScrollController _queueScrollController;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const _accent = Color(0xFF4A7EDB);

  Color get _bg => Theme.of(context).scaffoldBackgroundColor;
  Color get _text => Theme.of(context).colorScheme.onSurface;
  Color get _sub =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
  Color get _tile => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF2C2C2E)
      : const Color(0xFFE0E0E0);

  static Color _a(double a) => _accent.withValues(alpha: a);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _allScrollController = ScrollController();
    _songsScrollController = ScrollController();
    _videosScrollController = ScrollController();
    _favouritesScrollController = ScrollController();
    _queueScrollController = ScrollController();

    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {});
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
    _queueScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(MediaItem item) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    final title =
        (item.title ?? p.basenameWithoutExtension(item.path)).toLowerCase();
    final artist = (item.artist ?? '').toLowerCase();
    return title.contains(q) || artist.contains(q);
  }

  // ── Pick folder ────────────────────────────────────────────────────────

  Future<void> _pickFolder() async {
    if (kIsWeb) return;
    String? dirPath;
    try {
      dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select media folder',
      );
    } catch (e) {
      debugPrint('folder picker error: $e');
    }
    if (dirPath == null || !mounted) return;

    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;

    final items = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) {
          final ext = p.extension(f.path).toLowerCase();
          return PlayerState._mediaExtensions.contains(ext);
        })
        .map((f) {
          final ext = p.extension(f.path).toLowerCase();
          final isVideo = {
            '.mp4', '.mkv', '.avi', '.webm', '.mov', '.wmv', '.flv', '.m4v'
          }.contains(ext);
          return MediaItem(
            f.path,
            isVideo ? MediaType.video : MediaType.audio,
            title: p.basenameWithoutExtension(f.path),
          );
        })
        .toList();

    if (!mounted) return;
    await context.read<PlayerState>().setLibrary(items);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlayerState>();

    // Compute real counts for tab labels.
    final allCount = state.library
        .where((item) => state.folderItemCount == 0 ||
            state.library.indexOf(item) < state.folderItemCount)
        .length;
    final songCount = state.audioEntries.length;
    final videoCount = state.videoEntries.length;
    final favCount = state.favouriteEntries.length;
    final queueCount = state.manualQueue.length;

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            // ── Persistent video renderer ──
            _PersistentVideoWidget(
              mkController: state.videoController,
              androidController: state.androidVideoController,
              visible: state.isVideo &&
                  (state.videoController != null ||
                      state.androidVideoController != null),
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
                          Tab(text: 'All ($allCount)'),
                          Tab(text: '♪ Songs ($songCount)'),
                          Tab(text: '▶ Videos ($videoCount)'),
                          Tab(text: '★ Favourites ($favCount)'),
                          Tab(text: '⏭ Queue ($queueCount)'),
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
                        _queueTab(state),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
            IconButton(
              icon: Icon(Icons.folder_open,
                  color: Theme.of(context).colorScheme.onSurface),
              tooltip: 'Open folder',
              onPressed: _pickFolder,
            ),
          ],
        ),
      ),
    );
  }

  // ── Now playing bar ─────────────────────────────────────────────────────

  Widget _nowPlaying(PlayerState state) {
    final item = state.currentItem;
    if (item == null) {
      return const SizedBox.shrink();
    }

    final title = item.title ?? p.basenameWithoutExtension(item.path);
    final artist = item.artist ?? '';
    final dur = state.duration ?? Duration.zero;
    final pos = state.position;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: _tile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Track info row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.thumbnailData != null
                      ? Image.memory(item.thumbnailData!,
                          width: 48, height: 48, fit: BoxFit.cover)
                      : Container(
                          width: 48,
                          height: 48,
                          color: _a(0.15),
                          child: Icon(
                            item.type == MediaType.video
                                ? Icons.videocam
                                : Icons.music_note,
                            color: _accent,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                // Title / artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: _text)),
                      if (artist.isNotEmpty)
                        Text(artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 12, color: _sub)),
                    ],
                  ),
                ),
                // Favourite toggle
                IconButton(
                  icon: Icon(
                    state.isFavourite(item.path)
                        ? Icons.star
                        : Icons.star_border,
                    color: state.isFavourite(item.path)
                        ? Colors.amber
                        : _sub,
                    size: 22,
                  ),
                  onPressed: () => state.toggleFavourite(item.path),
                ),
              ],
            ),
          ),
          // Progress slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(_fmtDur(pos),
                    style: TextStyle(fontSize: 11, color: _sub)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: (dur.inMilliseconds > 0
                              ? pos.inMilliseconds /
                                  dur.inMilliseconds
                              : 0.0)
                          .clamp(0.0, 1.0),
                      activeColor: _accent,
                      inactiveColor: _a(0.25),
                      onChanged: dur.inMilliseconds > 0
                          ? (v) => state.seek(
                              Duration(
                                  milliseconds:
                                      (v * dur.inMilliseconds)
                                          .round()))
                          : null,
                    ),
                  ),
                ),
                Text(_fmtDur(dur),
                    style: TextStyle(fontSize: 11, color: _sub)),
              ],
            ),
          ),
          // Controls row
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Shuffle
                IconButton(
                  icon: Icon(Icons.shuffle,
                      color: state.shuffle ? _accent : _sub, size: 20),
                  onPressed: state.toggleShuffle,
                  tooltip: 'Shuffle',
                ),
                // Previous
                IconButton(
                  icon: Icon(Icons.skip_previous, color: _text, size: 28),
                  onPressed: () => state.previous(only: state.activeTabFilter),
                ),
                // Play / Pause
                Container(
                  decoration:
                      BoxDecoration(color: _accent, shape: BoxShape.circle),
                  child: IconButton(
                    icon: Icon(
                        state.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 28),
                    onPressed: state.togglePlay,
                  ),
                ),
                // Next
                IconButton(
                  icon: Icon(Icons.skip_next, color: _text, size: 28),
                  onPressed: () => state.next(only: state.activeTabFilter),
                ),
                // Repeat
                IconButton(
                  icon: Icon(
                    state.repeatMode == RepeatMode.one
                        ? Icons.repeat_one
                        : Icons.repeat,
                    color: state.repeatMode != RepeatMode.off
                        ? _accent
                        : _sub,
                    size: 20,
                  ),
                  onPressed: state.cycleRepeat,
                  tooltip: 'Repeat',
                ),
              ],
            ),
          ),
          // Volume slider
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Icon(Icons.volume_down, size: 18, color: _sub),
                Expanded(
                  child: Slider(
                    value: state.volume,
                    activeColor: _accent,
                    inactiveColor: _a(0.2),
                    onChanged: state.setVolume,
                  ),
                ),
                Icon(Icons.volume_up, size: 18, color: _sub),
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

  // ── Tabs ──────────────────────────────────────────────────────────────

  Widget _allTab(PlayerState state) {
    final audioFiltered = state.audioEntries
        .where((e) => _matchesSearch(e.value))
        .toList();
    final videoFiltered = state.videoEntries
        .where((e) => _matchesSearch(e.value))
        .toList();

    if (audioFiltered.isEmpty && videoFiltered.isEmpty) {
      return _emptyHint('No media in library.\nTap the folder icon to open a folder.');
    }

    // Build a flat list: songs header + songs + videos header + video grid rows
    final rows = <_AllTabItem>[];
    if (audioFiltered.isNotEmpty) {
      rows.add(_AllTabItem.header('Songs'));
      for (final e in audioFiltered) {
        rows.add(_AllTabItem.song(e));
      }
    }
    if (videoFiltered.isNotEmpty) {
      rows.add(_AllTabItem.header('Videos'));
      // Group into rows of 2 for a grid
      for (int i = 0; i < videoFiltered.length; i += 2) {
        final pair = videoFiltered.sublist(
            i, (i + 2).clamp(0, videoFiltered.length));
        rows.add(_AllTabItem.videoGrid(pair));
      }
    }

    return ListView.builder(
      controller: _allScrollController,
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        switch (row.kind) {
          case _AllTabKind.header:
            return _sectionHeader(row.headerText!);
          case _AllTabKind.song:
            return _songTile(state, row.entry!);
          case _AllTabKind.videoGrid:
            return _videoGridRow(state, row.entries!);
        }
      },
    );
  }

  Widget _songsTab(PlayerState state) {
    final filtered = state.audioEntries
        .where((e) => _matchesSearch(e.value))
        .toList();
    if (filtered.isEmpty) {
      return _emptyHint('No songs found.');
    }
    return ListView.builder(
      controller: _songsScrollController,
      itemCount: filtered.length,
      itemBuilder: (_, i) => _songTile(state, filtered[i]),
    );
  }

  Widget _videosTab(PlayerState state) {
    final filtered = state.videoEntries
        .where((e) => _matchesSearch(e.value))
        .toList();
    if (filtered.isEmpty) {
      return _emptyHint('No videos found.');
    }
    return GridView.builder(
      controller: _videosScrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 16 / 10,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: filtered.length,
      itemBuilder: (_, i) => _videoCard(state, filtered[i]),
    );
  }

  Widget _favouritesTab(PlayerState state) {
    final filtered = state.favouriteEntries
        .where((e) => _matchesSearch(e.value))
        .toList();
    if (filtered.isEmpty) {
      return _emptyHint('No favourites yet.\nTap ★ on a track to add it.');
    }
    return ListView.builder(
      controller: _favouritesScrollController,
      itemCount: filtered.length,
      itemBuilder: (_, i) => _songTile(state, filtered[i]),
    );
  }

  Widget _queueTab(PlayerState state) {
    if (state.manualQueue.isEmpty) {
      return _emptyHint('Queue is empty.\nLong-press a track to add it.');
    }
    return ReorderableListView.builder(
      scrollController: _queueScrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.manualQueue.length,
      onReorder: state.reorderQueue,
      itemBuilder: (_, i) {
        final idx = state.manualQueue[i];
        if (idx >= state.library.length) return const SizedBox.shrink(key: ValueKey(-1));
        final item = state.library[idx];
        final title = item.title ?? p.basenameWithoutExtension(item.path);
        return ListTile(
          key: ValueKey('q_$i'),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: item.thumbnailData != null
                ? Image.memory(item.thumbnailData!,
                    width: 40, height: 40, fit: BoxFit.cover)
                : Container(
                    width: 40,
                    height: 40,
                    color: _a(0.15),
                    child: Icon(
                      item.type == MediaType.video
                          ? Icons.videocam
                          : Icons.music_note,
                      color: _accent,
                      size: 18,
                    ),
                  ),
          ),
          title: Text(title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: item.artist != null
              ? Text(item.artist!,
                  maxLines: 1, overflow: TextOverflow.ellipsis)
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
    );
  }

  // ── Shared tile / card widgets ───────────────────────────────────────

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _sub,
              letterSpacing: 0.8)),
    );
  }

  Widget _emptyHint(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(color: _sub, fontSize: 14)),
      ),
    );
  }

  Widget _songTile(PlayerState state, MapEntry<int, MediaItem> e) {
    final item = e.value;
    final idx = e.key;
    final isPlaying =
        state.currentIndex == idx && state.isActuallyPlaying;
    final title = item.title ?? p.basenameWithoutExtension(item.path);

    return VisibilityDetector(
      key: Key('song_$idx'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.1) {
          state.requestThumbnailForIndex(idx);
        }
      },
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: item.thumbnailData != null
              ? Image.memory(item.thumbnailData!,
                  width: 44, height: 44, fit: BoxFit.cover)
              : Container(
                  width: 44,
                  height: 44,
                  color: _a(0.12),
                  child: Icon(Icons.music_note,
                      color: _accent, size: 22),
                ),
        ),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: isPlaying
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: isPlaying ? _accent : _text)),
        subtitle: item.artist != null
            ? Text(item.artist!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: _sub))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPlaying)
              Icon(Icons.equalizer, color: _accent, size: 18),
            IconButton(
              icon: Icon(
                state.isFavourite(item.path)
                    ? Icons.star
                    : Icons.star_border,
                size: 18,
                color: state.isFavourite(item.path)
                    ? Colors.amber
                    : _sub,
              ),
              onPressed: () => state.toggleFavourite(item.path),
            ),
          ],
        ),
        onTap: () => state.select(idx),
        onLongPress: () {
          state.enqueue(idx);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added "$title" to queue'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
    );
  }

  Widget _videoGridRow(
      PlayerState state, List<MapEntry<int, MediaItem>> entries) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: entries.map((e) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _videoCard(state, e),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _videoCard(PlayerState state, MapEntry<int, MediaItem> e) {
    final item = e.value;
    final idx = e.key;
    final isPlaying =
        state.currentIndex == idx && state.isActuallyPlaying;
    final title = item.title ?? p.basenameWithoutExtension(item.path);

    return VisibilityDetector(
      key: Key('video_$idx'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.1) {
          state.requestThumbnailForIndex(idx);
        }
      },
      child: GestureDetector(
        onTap: () => state.select(idx),
        onLongPress: () {
          state.enqueue(idx);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added "$title" to queue'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              // Thumbnail
              AspectRatio(
                aspectRatio: 16 / 9,
                child: item.thumbnailData != null
                    ? Image.memory(item.thumbnailData!,
                        fit: BoxFit.cover)
                    : Container(
                        color: _tile,
                        child: Icon(Icons.videocam,
                            color: _accent, size: 32),
                      ),
              ),
              // Overlay
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black26,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isPlaying)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.play_circle,
                      color: Colors.white, size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }
}