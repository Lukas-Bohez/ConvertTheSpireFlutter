# Collaborator Setup Guide

This document explains how to add collaborators and get them started on the project.

## Adding Collaborators on GitHub

1. Go to **https://github.com/Lukas-Bohez/ConvertTheSpireFlutter**
2. Click **Settings** → **Collaborators** (under "Access")
3. Click **Add people**
4. Search for and add:
   - `fgmnts`
   - `MLoth`
5. They will receive an email invitation — they must accept before they can push

> **Note:** On free GitHub plans, the repository must be **public** for collaborators to have push access. If the repo is private, you need GitHub Pro or a GitHub Organization.

## Collaborator Quick Start

Once invited, each collaborator should:

```bash
# 1. Clone the repository
git clone https://github.com/Lukas-Bohez/ConvertTheSpireFlutter.git
cd ConvertTheSpireFlutter

# 2. Ensure Flutter 3.27.4 is installed
flutter --version
# If not 3.27.4: flutter channel stable && flutter upgrade

# 3. Install dependencies
flutter pub get

# 4. Verify everything compiles
flutter analyze
dart analyze lib/

# 5. Run on your platform
flutter run                    # Default device
flutter run -d windows         # Windows desktop
flutter run -d linux           # Linux desktop
flutter run -d <device-id>     # Android (use `flutter devices` to list)
```

## Development Workflow

```bash
# Create a feature branch
git checkout -b feature/my-feature

# Make changes, then verify
flutter analyze
flutter test   # if test files exist

# Commit and push
git add .
git commit -m "feat: description of change"
git push origin feature/my-feature

# Open a Pull Request on GitHub
```

The CI pipeline runs automatically on every push and PR — check the **Actions** tab for build status.

## Platform-Specific Setup

### Windows
- No extra setup needed — Flutter handles everything
- For MSIX packaging: `dart run msix:create`

### Linux
```bash
sudo apt install clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-9-dev \
  libmpv-dev mpv libass-dev \
  libayatana-appindicator3-dev
```

### Android
- Install Android Studio or the Android SDK command-line tools
- Accept licenses: `flutter doctor --android-licenses`
- Connect a device or start an emulator

## Key Directories

| Directory | Contents |
|-----------|----------|
| `lib/src/screens/` | All UI screens |
| `lib/src/services/` | Business logic services |
| `lib/src/state/` | AppController (Provider-based state) |
| `lib/src/models/` | Data models |
| `lib/src/widgets/` | Reusable widgets |
| `.github/workflows/` | CI/CD pipeline |
| `scripts/` | Build helper scripts |
