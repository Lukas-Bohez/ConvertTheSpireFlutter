# Manual Action Checklist

All code and configuration changes have been applied. The following manual steps must be completed by the repository owner.

## Before Pushing

- [ ] Review all changes: `git diff`
- [ ] Stage and commit:
  ```bash
  git add -A
  git commit -m "feat: CI/CD pipeline, README, collaborator docs, bug fixes"
  ```

## GitHub Repository Setup

- [ ] **Push to main:**
  ```bash
  git push origin main
  ```
- [ ] **Verify CI runs:** Go to https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/actions and confirm the "CI/CD Pipeline" workflow passes the `quality` job

## Add Collaborators (before March 12 deadline)

- [ ] Go to https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/settings/access
- [ ] Click "Add people" → search `fgmnts` → invite
- [ ] Click "Add people" → search `MLoth` → invite
- [ ] Confirm both have accepted their invitations

## First Release

When ready to publish the first release:

- [ ] Tag the release:
  ```bash
  git tag v1.0.0
  git push origin v1.0.0
  ```
- [ ] Wait for CI to build all 3 platforms (~10-15 minutes)
- [ ] Verify the release appears at https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases

## Android Signing (Optional)

For signed Android APKs in CI, set up these repository secrets:

- [ ] Generate a keystore:
  ```bash
  keytool -genkey -v -keystore release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias release
  ```
- [ ] Encode it:
  ```bash
  base64 -w 0 release-key.jks > keystore.b64
  ```
- [ ] Go to https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/settings/secrets/actions
- [ ] Add secrets:
  - `KEYSTORE_BASE64` — contents of `keystore.b64`
  - `KEYSTORE_PASSWORD` — the password you chose
  - `KEY_ALIAS` — `release` (or whatever alias you used)
  - `KEY_PASSWORD` — the key password

## Local Build Verification (Optional)

Test local builds before relying on CI:

```bash
# Windows
flutter build windows --release

# Linux (in WSL or native)
flutter build linux --release

# Android
flutter build apk --release --split-per-abi
```

## Files Changed in This Session

### New Files
- `.github/workflows/ci.yml` — Full CI/CD pipeline (quality + 3 platform builds + release)
- `COLLABORATOR_SETUP.md` — Collaborator onboarding guide
- `MANUAL_ACTIONS.md` — This checklist

### Modified Files
- `README.md` — Comprehensive rewrite with architecture, IoT relevance, assignment breakdown
- `lib/src/screens/browser_screen.dart` — URL normalization + YouTube variant fixes
- `lib/src/screens/compute_screen.dart` — Gamification redesign
- `lib/src/screens/home_screen.dart` — Compute tab moved to position 8
- `lib/src/services/download_service.dart` — Additional error translations
- `lib/src/services/dlna_discovery_service.dart` — SSDP race condition fix
- `lib/src/services/coordinator_service.dart` — Connection state fix
- `pubspec.yaml` — Removed unused shelf and network_info_plus dependencies
