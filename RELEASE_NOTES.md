# Release Notes — v13.0.4

## What's New
- **Downloads are far more resilient to YouTube's frequent player/extractor changes.** When a download hits "The page needs to be reloaded" or `UNPLAYABLE`, the app auto-updates yt-dlp and retries once, so most transient YouTube breakage now self-heals without the user touching anything.
- **Bundled JavaScript runtime for yt-dlp** — the app now provisions a standalone Deno binary (or reuses a system Deno/Node install) so YouTube's signature/extraction code can always be evaluated, removing a whole class of "page needs to be reloaded" failures.
- Cinematic view removed (continues from v13.0.3).

## Bug Fixes
- Auto-update on reload/UNPLAYABLE errors, throttled (2h/session) to avoid hammering the GitHub API.
- Best-effort self-update on boot kept for keeping the bundled yt-dlp fresh.

See [CHANGELOG.md](CHANGELOG.md) for fuller details.
