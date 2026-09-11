#!/bin/bash
# =============================================================================
# single_download.sh — Standalone single-track downloader for ConvertTheSpire
#
# Mirrors the yt-dlp configuration used by the app's YtDlpService.download()
# (lib/src/services/yt_dlp_service.dart) so that command-line downloads match
# the app's pipeline exactly: same format selection, metadata embedding,
# extractor args, retry policy, and thumbnail cover embedding.
#
# Usage:
#   ./single_download.sh <URL>                        # mp3 @ 192kbps (default)
#   ./single_download.sh -f m4a -b 256 <URL>         # m4a @ 256kbps
#   ./single_download.sh -f mp4 -o ~/Music <URL>     # mp4 video (720p)
#   YTDLP=/path/to/yt-dlp ./single_download.sh <URL> # custom yt-dlp binary
#
# Requirements:
#   - yt-dlp (>= 2024-01) on PATH or set via YTDLP env var
#   - ffmpeg (for audio extraction / video merging / thumbnail embedding)
#   - Node.js or Deno (optional — for yt-dlp's JS runtime / nsig extraction)
# =============================================================================
set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────
YTDLP="${YTDLP:-yt-dlp}"
FORMAT="mp3"          # mp3 | m4a | mp4
OUTPUT_DIR="$(pwd)/downloads"
BITRATE=192           # kbps, clamped to 64–320 by yt-dlp --audio-quality
VIDEO_HEIGHT="${VIDEO_HEIGHT:-720}"  # max height px for mp4 video downloads

# ── Help ──────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $0 <URL> [options]

Options:
  -f, --format <fmt>      Output format: mp3 (default), m4a, mp4
  -o, --output <dir>      Output directory  (default: ./downloads)
  -b, --bitrate <kbps>    Audio bitrate 64–320 (default: 192)
  -v, --height <px>       Max video height for mp4  (default: 720)
  -y, --yt-dlp <path>     Path to yt-dlp binary  (default: yt-dlp on PATH)
  -h, --help              Show this help

Examples:
  $0 "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  $0 -f m4a -b 256 "https://youtu.be/xxxxxxxxxxx"
  $0 -f mp4 -o ~/Music "https://www.youtube.com/watch?v=xxxxxxxxxxx"
EOF
    exit 0
}

# ── Parse args ────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--format)    FORMAT="$2"; shift 2 ;;
        -o|--output)    OUTPUT_DIR="$2"; shift 2 ;;
        -b|--bitrate)   BITRATE="$2"; shift 2 ;;
        -v|--height)    VIDEO_HEIGHT="$2"; shift 2 ;;
        -y|--yt-dlp)    YTDLP="$2"; shift 2 ;;
        -h|--help)      usage ;;
        -*)             echo "Unknown option: $1" >&2; exit 1 ;;
        *)              URL="$1"; shift ;;
    esac
done

if [[ -z "${URL:-}" ]]; then
    echo "Error: URL is required." >&2
    echo "Run '$0 --help' for usage." >&2
    exit 1
fi

# ── Validate yt-dlp ───────────────────────────────────────────────────────
if ! command -v "$YTDLP" >/dev/null 2>&1; then
    echo "Error: yt-dlp not found at '$YTDLP'." >&2
    echo "Install it from https://github.com/yt-dlp/yt-dlp or set YTDLP env var." >&2
    exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Warning: ffmpeg not found — audio extraction and thumbnail embedding may fail." >&2
fi

# ── Validate format ───────────────────────────────────────────────────────
case "$FORMAT" in
    mp3|m4a|mp4) ;;
    *)
        echo "Error: unsupported format '$FORMAT'. Use: mp3, m4a, mp4" >&2
        exit 1
        ;;
esac

# ── Clamp bitrate ─────────────────────────────────────────────────────────
BITRATE=$(echo "$BITRATE" | awk '{v=$1; if(v<64) v=64; if(v>320) v=320; print int(v)}')

# ── Create output directory ──────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

# ── Build yt-dlp arguments ────────────────────────────────────────────────
# These mirror YtDlpService.download() in lib/src/services/yt_dlp_service.dart
ARGS=(
    --no-mtime
    --extractor-args "youtube:lang=en"
    --no-playlist
    --newline
    --no-colors
    --no-overwrites
    --no-part
    --extractor-retries 3
    --retries 10
    --embed-metadata
    --embed-thumbnail
    --add-metadata
    --extractor-args "youtube:player_client=tv,web"
)

if [[ "$FORMAT" == "mp4" ]]; then
    # Video: best video+audio up to target height, merged to mp4
    ARGS+=(
        -f "bestvideo[height<=${VIDEO_HEIGHT}]+bestaudio/best[height<=${VIDEO_HEIGHT}]"
        --merge-output-format mp4
    )
else
    # Audio: extract audio from best available
    ARGS+=(
        -f "bestaudio/best"
        -x
        --audio-format "$FORMAT"
        --audio-quality "${BITRATE}k"
    )
fi

# Output template: <dir>/<title>.<ext>
ARGS+=(-o "${OUTPUT_DIR}/%(title)s.%(ext)s")

# ── Run ───────────────────────────────────────────────────────────────────
echo "Downloading →  $FORMAT  |  $URL  |  output: $OUTPUT_DIR"
echo "yt-dlp: $YTDLP  |  bitrate: ${BITRATE}kbps  |  height: ${VIDEO_HEIGHT}p"
"$YTDLP" "${ARGS[@]}" "$URL"
echo "Done: $(ls -1 "$OUTPUT_DIR" | wc -l) file(s) in $OUTPUT_DIR"
