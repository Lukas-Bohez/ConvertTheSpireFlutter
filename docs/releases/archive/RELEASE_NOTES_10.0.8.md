# Release Notes 10.0.8

Version: 10.0.8+1008
Date: 2026-04-22

## Summary
This release completes a broad quality audit pass focused on layout safety, adaptive UI behavior, player UX, browser responsiveness, torrent management reliability, settings/about robustness, and performance tuning.

## Highlights
- Added global adaptive frame integration for both main app and vault app roots.
- Expanded overflow safety across dialogs and constrained layouts.
- Improved torrent screen keyboard/mouse navigation and responsive list/grid behavior.
- Added buffered seek visualization in mini player slider.
- Improved mini player control responsiveness for compact widths.
- Standardized browser toolbar breakpoints for compact/standard/expanded layouts.
- Added optional "remove + delete files" flow for torrents.
- Made privacy policy row actionable from settings/about screen.
- Added real diagnostics export to JSON file with timestamp persistence.
- Added debounced torrent search input to reduce rebuild churn.

## Validation
- `flutter analyze`: clean after each subtask and final pass.
- `flutter test`: all tests passed.

## TECH-DEBT
- Mini player overlay still does not expose explicit sleep timer controls.
- Mini player overlay still does not expose playback speed controls.
- Full cross-surface sleep timer countdown plumbing remains a follow-up task.

## Notes
- Android App Bundle for this version is generated and copied to `aab/`.
