# ============================================================================
# FIX: ffmpeg_kit_flutter_new uses an old AGP version, which causes R8 to
# mis-optimize FlutterPlugin implementations, breaking Pigeon-based channels
# (path_provider, shared_preferences, etc.) in release builds.
# See: https://github.com/flutter/flutter/issues/153075
#      https://github.com/flutter/flutter/issues/154580
# ============================================================================

# Keep FFmpegKit classes — their old AGP confuses R8 plugin registration
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keep class com.arthenica.** { *; }

# Keep ALL FlutterPlugin implementations (remove allowoptimization to prevent
# R8 from inlining/merging plugin registration code)
-keep,allowshrinking,allowobfuscation class * implements io.flutter.embedding.engine.plugins.FlutterPlugin

# Keep Flutter Pigeon-generated classes used by path_provider_android and other plugins.
-keep class dev.flutter.pigeon.** { *; }

# Keep path_provider plugin classes
-keep class io.flutter.plugins.pathprovider.** { *; }

# Keep shared_preferences plugin classes
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Keep all Flutter plugin registrant classes
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep all Flutter embedding classes
-keep class io.flutter.embedding.** { *; }

# Keep file_picker plugin classes
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Suppress warnings for Google Play Core classes (not needed for non-Play Store builds)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
