import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// The app's id on Linux: the runner's APPLICATION_ID (linux/CMakeLists.txt),
/// its Flathub id. Desktops match windows to the menu entry of the same name.
const linuxAppId = 'io.github.Lukas_Bohez.ConvertTheSpireFlutter';

/// The id up to 16.4.0, Flutter's template one.
const oldLinuxAppId = 'com.example.convert_the_spire_reborn';

/// Whether the app runs as a Flatpak.
bool get isFlatpak =>
    !kIsWeb &&
    Platform.isLinux &&
    (Platform.environment['FLATPAK_ID']?.isNotEmpty ?? false);

/// The app keeps its settings and data in a folder named after its id
/// (`~/.local/share/<id>` and `~/.config/<id>`): the folder under the old id is
/// moved to the new one, once, before anything reads them. A Flatpak has its
/// own folders and cannot see these.
Future<void> moveLinuxDataToNewAppId() async {
  if (kIsWeb || !Platform.isLinux || isFlatpak) return;
  final env = Platform.environment;
  final home = env['HOME'];
  if (home == null || home.isEmpty) return;
  String base(String variable, List<String> fallback) =>
      env[variable]?.isNotEmpty == true
          ? env[variable]!
          : p.joinAll([home, ...fallback]);
  for (final root in [
    base('XDG_DATA_HOME', ['.local', 'share']),
    base('XDG_CONFIG_HOME', ['.config']),
  ]) {
    await moveAppIdFolder(root);
  }
}

/// Moves `[root]/<old id>` to `[root]/<new id>` when only the old one exists.
@visibleForTesting
Future<void> moveAppIdFolder(String root) async {
  final old = Directory(p.join(root, oldLinuxAppId));
  final current = Directory(p.join(root, linuxAppId));
  try {
    if (!await old.exists() || await current.exists()) return;
    await old.rename(current.path);
    debugPrint('Moved ${old.path} to ${current.path}');
  } catch (e) {
    debugPrint('Could not move ${old.path}: $e');
  }
}
