import 'package:package_info_plus/package_info_plus.dart';

/// Holds the detected application flavor and exposes a small initializer
/// that must be called early from `main()` before most other initialization
/// so that synchronous checks (e.g. `kPlayStoreBuild`) are valid.
String appFlavorLabel = '';

Future<void> initAppFlavor() async {
  try {
    final info = await PackageInfo.fromPlatform();
    appFlavorLabel = info.appName.toLowerCase();
  } catch (_) {
    appFlavorLabel = '';
  }
}

/// Returns true when the app label matches the Play Store branding.
bool get isPlayFlavor => appFlavorLabel.contains('bitplayer') || appFlavorLabel == 'bitplayer';
