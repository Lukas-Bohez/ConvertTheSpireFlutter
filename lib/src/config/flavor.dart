import 'package:package_info_plus/package_info_plus.dart';

/// Holds the detected application flavor and exposes a small initializer
/// that must be called early from `main()` before most other initialization
/// so that synchronous checks (e.g. `kPlayStoreBuild`) are valid.
String appFlavorLabel = '';
String appPackageName = '';

Future<void> initAppFlavor() async {
  try {
    final info = await PackageInfo.fromPlatform();
    appFlavorLabel = info.appName.toLowerCase();
    appPackageName = info.packageName.toLowerCase();
  } catch (_) {
    appFlavorLabel = '';
    appPackageName = '';
  }
}

/// Returns true for the Play Store Android package id.
///
/// We intentionally detect flavor by package id instead of app label so
/// branding can stay consistent across all distributions.
bool get isPlayFlavor => appPackageName == 'com.torrentspire.ai';
