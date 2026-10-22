import 'dart:io';

import 'package:path/path.dart' as p;

/// The name a finished download is saved under (issue #45, fix 8).
///
/// Downloads used to be named after the title alone, so two different videos
/// with the same title (every upload of a channel called "Sasaki", say) got
/// the same file. The second one then replaced the first, or a failed second
/// one deleted it. Now a name that is already taken by something else gets
/// the video id, the way yt-dlp names files itself: `Title [id].mp3`.
class NameChoice {
  const NameChoice(this.name, {this.replace = false});

  final String name;

  /// The name is taken by an earlier download of the same video, which this
  /// one replaces.
  final bool replace;

  @override
  String toString() => replace ? '$name (replaces)' : name;
}

class DownloadNaming {
  DownloadNaming._();

  /// A YouTube id in a file name, as `[xxxxxxxxxxx]`.
  static final RegExp idInName = RegExp(r'\[([A-Za-z0-9_-]{11})\]');

  /// The YouTube id a file name carries, or null.
  static String? idFromName(String fileName) =>
      idInName.firstMatch(fileName)?.group(1);

  /// Picks the name for [stem].[ext] in a folder where [taken] says which
  /// names are in use. Names are compared without case: Windows and Android
  /// folders treat `Song` and `song` as the same file.
  ///
  /// - The plain name when it is free.
  /// - The plain name, replacing, when it is [replaceableName]: the file an
  ///   earlier download of this same video left.
  /// - `stem [videoId]` when the plain name is someone else's. If that is
  ///   taken too, it can only be this video, which it replaces.
  /// - Without an id: `stem (2)`, `stem (3)`, ...
  static NameChoice choose({
    required String stem,
    required String ext,
    required bool Function(String name) taken,
    String? videoId,
    String? replaceableName,
  }) {
    final plain = '$stem.$ext';
    if (!taken(plain)) return NameChoice(plain);
    if (replaceableName != null &&
        replaceableName.toLowerCase() == plain.toLowerCase()) {
      return NameChoice(plain, replace: true);
    }
    if (videoId != null && videoId.isNotEmpty && !stem.contains('[$videoId]')) {
      final withId = '$stem [$videoId].$ext';
      return NameChoice(withId, replace: taken(withId));
    }
    for (var n = 2; n < 1000; n++) {
      final numbered = '$stem ($n).$ext';
      if (!taken(numbered)) return NameChoice(numbered);
    }
    return NameChoice('$stem (${DateTime.now().millisecondsSinceEpoch}).$ext');
  }

  /// Moves the finished file [source] into [folder] under the name [choose]
  /// picks, and returns where it went. Nothing in [folder] is replaced except
  /// an earlier download of the same video.
  static Future<String> placeLocal({
    required String source,
    required Directory folder,
    required String stem,
    required String ext,
    String? videoId,
    String? replaceablePath,
  }) async {
    await folder.create(recursive: true);
    final existing = <String, String>{};
    await for (final entity in folder.list(followLinks: false)) {
      final name = p.basename(entity.path);
      existing[name.toLowerCase()] = entity.path;
    }
    final replaceableName = replaceablePath != null &&
            p.equals(p.dirname(replaceablePath), folder.path)
        ? p.basename(replaceablePath)
        : null;

    for (var attempt = 0; attempt < 5; attempt++) {
      final choice = choose(
        stem: stem,
        ext: ext,
        taken: (name) => existing.containsKey(name.toLowerCase()),
        videoId: videoId,
        replaceableName: replaceableName,
      );
      final dest = p.join(folder.path, choice.name);
      if (choice.replace) {
        final old = existing[choice.name.toLowerCase()];
        if (old != null) await _deleteIfFile(old);
      } else if (await FileSystemEntity.type(dest) !=
          FileSystemEntityType.notFound) {
        // Another download finished under this name a moment ago.
        existing[choice.name.toLowerCase()] = dest;
        continue;
      }
      await moveFile(source, dest);
      return dest;
    }
    throw FileSystemException('No free name for "$stem.$ext"', folder.path);
  }

  /// Renames [from] to [to], copying when they are on different drives.
  static Future<void> moveFile(String from, String to) async {
    try {
      await File(from).rename(to);
    } on FileSystemException {
      await File(from).copy(to);
      try {
        await File(from).delete();
      } catch (_) {}
    }
  }

  /// A fresh folder of its own for one download's files while it runs.
  /// Cleaning up after a failed or cancelled download empties this folder
  /// and nothing else, so a file with the same name in the real download
  /// folder can never be touched.
  static Future<Directory> createWorkDir(Directory base) async {
    final dir = Directory(p.join(base.path,
        'dl_${DateTime.now().microsecondsSinceEpoch}_${pid.toRadixString(36)}'));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<void> _deleteIfFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
