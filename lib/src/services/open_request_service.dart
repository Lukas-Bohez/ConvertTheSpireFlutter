import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

/// What the app was asked to open from outside.
enum OpenRequestKind { magnet, torrentFile, media }

/// A file or link the app was asked to open: "Open with" or a double-click in
/// Explorer or Finder, a file manager on a phone, a magnet link in a browser.
@immutable
class OpenRequest {
  const OpenRequest(this.kind, this.target,
      {required this.name, this.isVideo = false});

  final OpenRequestKind kind;

  /// A magnet link, a file path, or an Android content:// address.
  final String target;

  /// The file name, which a content:// address does not show. Empty for a
  /// magnet link.
  final String name;

  /// For [OpenRequestKind.media]: a video rather than a song.
  final bool isVideo;

  @override
  bool operator ==(Object other) =>
      other is OpenRequest &&
      other.kind == kind &&
      other.target == target &&
      other.name == name &&
      other.isVideo == isVideo;

  @override
  int get hashCode => Object.hash(kind, target, name, isVideo);

  @override
  String toString() => 'OpenRequest($kind, $target, $name, video: $isVideo)';
}

/// Collects files and links the app was asked to open and hands them to the
/// home screen.
///
/// Each platform queues them natively (MainActivity on Android, the runner on
/// Windows, AppDelegate on macOS) on the "convert_the_spire/open" channel.
/// This service takes the queue at startup, whenever the app resumes, and when
/// the native side says "pending", so nothing is lost while Flutter is still
/// starting.
class OpenRequestService with WidgetsBindingObserver {
  OpenRequestService._();

  static final OpenRequestService instance = OpenRequestService._();

  static const MethodChannel _channel = MethodChannel('convert_the_spire/open');

  /// The formats the player plays: PlayerState._mediaExtensions. The Windows
  /// runner (open_requests.cpp), AndroidManifest.xml and the macOS
  /// Info.plist offer the app for the same ones.
  static const Set<String> mediaExtensions = {
    '.mp3',
    '.m4a',
    '.flac',
    '.wav',
    '.ogg',
    '.opus',
    '.aac',
    '.wma',
    '.mp4',
    '.mkv',
    '.avi',
    '.webm',
    '.mov',
    '.wmv',
    '.flv',
    '.m4v',
  };

  static const Set<String> _videoExtensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.webm',
    '.mov',
    '.wmv',
    '.flv',
    '.m4v',
  };

  final List<OpenRequest> _waiting = [];
  final StreamController<void> _arrived = StreamController<void>.broadcast();
  bool _started = false;

  /// Fires when requests are waiting in [takeAll].
  Stream<void> get onArrived => _arrived.stream;

  /// True on the platforms that pass opened files and links to the app.
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows || Platform.isMacOS);

  void start() {
    if (_started || !isSupported) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pending') await _takePending();
    });
    WidgetsBinding.instance.addObserver(this);
    unawaited(_takePending());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_takePending());
  }

  /// Returns the waiting requests and forgets them.
  List<OpenRequest> takeAll() {
    final taken = List<OpenRequest>.of(_waiting);
    _waiting.clear();
    return taken;
  }

  Future<void> _takePending() async {
    List<Object?>? raw;
    try {
      raw = await _channel.invokeListMethod<Object?>('takePending');
    } on MissingPluginException {
      return;
    } catch (e) {
      debugPrint('OpenRequestService: takePending failed: $e');
      return;
    }
    // A second start of the app with nothing to open still sends "pending",
    // to bring the window forward: announce it even when the list is empty.
    for (final item in raw ?? const <Object?>[]) {
      final request = item is Map
          ? classify(
              item['uri']?.toString() ?? '',
              name: item['name']?.toString(),
              mimeType: item['mimeType']?.toString(),
            )
          : classify(item?.toString() ?? '');
      if (request != null) _waiting.add(request);
    }
    _arrived.add(null);
  }

  /// Works out what [raw] is: a command-line argument, a file path, a
  /// file:// or content:// address, or a magnet link. [name] and [mimeType]
  /// come with Android content:// addresses. Returns null for anything the
  /// app does not open, such as a command-line flag.
  @visibleForTesting
  static OpenRequest? classify(String raw, {String? name, String? mimeType}) {
    var target = raw.trim();
    if (target.length >= 2 && target.startsWith('"') && target.endsWith('"')) {
      target = target.substring(1, target.length - 1).trim();
    }
    if (target.isEmpty || target.startsWith('-')) return null;

    final lower = target.toLowerCase();
    if (lower.startsWith('magnet:')) {
      return OpenRequest(OpenRequestKind.magnet, target, name: '');
    }

    if (lower.startsWith('file://')) {
      try {
        target = Uri.parse(target).toFilePath();
      } catch (_) {
        return null;
      }
    }
    final isContentUri = lower.startsWith('content://');
    var fileName = name?.trim() ?? '';
    if (fileName.isEmpty) {
      fileName = isContentUri
          ? Uri.tryParse(target)?.pathSegments.lastOrNull ?? ''
          : p.basename(target);
    }
    final extension = p.extension(fileName).toLowerCase();
    final type = mimeType?.toLowerCase() ?? '';

    if (extension == '.torrent' || type == 'application/x-bittorrent') {
      return OpenRequest(OpenRequestKind.torrentFile, target, name: fileName);
    }
    if (mediaExtensions.contains(extension) ||
        type.startsWith('audio/') ||
        type.startsWith('video/')) {
      final isVideo = type.startsWith('video/') ||
          (!type.startsWith('audio/') && _videoExtensions.contains(extension));
      return OpenRequest(OpenRequestKind.media, target,
          name: fileName, isVideo: isVideo);
    }
    return null;
  }
}
