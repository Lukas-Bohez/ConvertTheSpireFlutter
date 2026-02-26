# My Flutter App

This is a Flutter application designed to demonstrate the functionality of a mobile app using Flutter framework. 

## Project Structure

```
my_flutter_app
├── android                # Android platform-specific code
├── ios                    # iOS platform-specific code
├── lib                    # Main application code
│   ├── main.dart          # Entry point of the application
│   ├── src                # Source files for the app
│   │   ├── app.dart       # Main application widget
│   │   ├── screens        # Contains different screens of the app
│   │   │   └── home_screen.dart # Home screen layout and logic
│   │   ├── widgets        # Reusable widgets
│   │   │   └── reusable_widget.dart # A reusable widget class
│   │   ├── models         # Data models
│   │   │   └── item_model.dart # Structure of an item
│   │   └── services       # Services for API calls
│   │       └── api_service.dart # Handles API interactions
├── test                   # Test files
│   └── widget_test.dart   # Widget tests for the application
├── pubspec.yaml           # Project configuration and dependencies
├── analysis_options.yaml   # Dart analyzer configuration
├── .gitignore             # Files to ignore in version control
└── README.md              # Project documentation
```

## Getting Started

To get started with this project, ensure you have Flutter installed on your machine. You can follow the official Flutter installation guide [here](https://flutter.dev/docs/get-started/install).

### Installation

1. Clone the repository:
   ```
   git clone <repository-url>
   ```
2. Navigate to the project directory:
   ```
   cd my_flutter_app
   ```
3. Install the dependencies:
   ```
   flutter pub get
   ```

### Running the App

To run the app, use the following command:
```
flutter run
```

> **First launch**: the application will automatically display a brief onboarding tour covering each of the main tabs. During the tour you’ll now see small previews and mock‑ups of the features being described (for example, the **Queue** page shows a mini list with status icons) so you get an immediate feel for what the real screen looks like. The tour also exposes a theme toggle which calls back to the host, allowing you to switch between light/dark/auto without leaving the walkthrough. You can revisit the tour at any time via the "Show onboarding" button at the top of the **Guide** tab.

To wire it up in your own app pass the active `ThemeMode` and handle changes:

```dart
OnboardingScreen(
  onFinish: _markSeen,
  themeMode: _themeMode,
  onThemeChanged: (mode) => setState(() => _themeMode = mode),
)
```

### Testing

To run the widget tests, use:
```
flutter test
```

## Contributing

Contributions are welcome! Please feel free to submit a pull request or open an issue for any suggestions or improvements.

## License

This project is licensed under the GNU GPLv3. See [LICENSE](LICENSE) for details.

## Native library requirements

This application uses [`package:media_kit`](https://pub.dev/packages/media_kit)
for video playback.  `media_kit` is a thin Dart wrapper around the native
`libmpv` library – the MPV media player core – which **is not bundled with
the Dart package**.  You must supply the appropriate `libmpv` binaries for
each target platform before the player can be used.

### Android

* **Important:** the `media_kit` Dart package currently does **not** support
  video playback on Android.  Even if you bundle the native `libmpv.so` files
  correctly, the plugin throws `Unsupported platform: android` during
  initialization.  The app has been updated to gracefully disable video and
  fall back to audio-only behaviour on Android, but you should not expect
  video playback to work until a future release of `media_kit` adds Android
  support.

* Add the `.so` files for each ABI you intend to support under
  `android/app/src/main/jniLibs/<abi>/libmpv.so`.  Prebuilt libraries can be
  downloaded from the [media_kit GitHub releases](https://github.com/media-kit/media-kit/releases)
  (look for `android-arm64-v8a`, `android-armeabi-v7a`, etc.).  To automate
  the process you can run one of the helper scripts included in this
  repository:

  ```bash
  # bash (Linux/macOS/WSL)
  chmod +x scripts/fetch_mpv_android.sh && scripts/fetch_mpv_android.sh

  # PowerShell (Windows)
  scripts\fetch_mpv_android.ps1
  ```

  The script downloads the appropriate APKs from the release and extracts the
  `libmpv.so` into the correct `jniLibs` subfolders.  (This step is harmless
  on Android and will be necessary once support is added.)
* When building APKs make sure you either build an Android App Bundle or add
  `--split-per-abi` to your `flutter build apk` command; the library is large
  and Gradle will strip it out of fat APKs unless the split is enabled, which
  leads to the runtime error `Cannot find libmpv.so`.  (The error screen you
  now see explains the problem.)
* Our runtime checks will display a friendly error page if the library is
  missing, rather than crashing to a black screen.
### Linux

Install the system packages so that `libmpv` is available at runtime:

```bash
sudo apt install libmpv-dev mpv  # Debian/Ubuntu
# or the equivalent for your distro
```
The application will catch initialization failures and show an error message
with these instructions.

Important: video playback on Linux requires the system `libmpv` (mpv) runtime.
If you want video support, install `mpv` / `libmpv` (examples above) or
ensure your target distribution bundles `libmpv` alongside the app. Without
`libmpv` the app will fall back to audio-only behaviour and display a
helpful message explaining how to install it.

The application will catch initialization failures and show an error message
with these instructions.

### iOS / macOS / Windows

Binaries for these platforms are currently bundled automatically by the
`media_kit` plugin (via the `media_kit_video` and
`media_kit_libs_windows_video` packages), so no manual steps are required.

---

## Support

Buy me a coffee: https://buymeacoffee.com/orokaconner
Website: https://quizthespire.com/