# Keep Flutter Pigeon-generated classes used by path_provider_android and other plugins.
# R8 can strip these classes in release builds, breaking platform channel connections.
-keep class dev.flutter.pigeon.** { *; }

# Keep path_provider plugin classes
-keep class io.flutter.plugins.pathprovider.** { *; }

# Keep all Flutter plugin registrant classes
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep all Flutter embedding classes
-keep class io.flutter.embedding.** { *; }

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
