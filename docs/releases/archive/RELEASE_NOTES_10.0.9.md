# Release Notes 10.0.9

Version: 10.0.9+1009
Date: 2026-04-22

## Summary
Play Store release build refresh with the Play-only feature flags enabled and prior full-mode bundles removed.

## Notes
- Play Store build uses `--flavor play --release --dart-define=PLAY_STORE_BUILD=true`.
- Forbidden YouTube conversion paths remain disabled in Play Store builds.
- Play-only tab visibility and limited-mode branding remain enforced by build flags.

## Validation
- Old release bundles removed from `aab/`.
- New Play Store AAB will be generated in `aab/ConvertTheSpireReborn.aab`.
