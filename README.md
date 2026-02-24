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

## Support

Buy me a coffee: https://buymeacoffee.com/orokaconner
Website: https://quizthespire.com/