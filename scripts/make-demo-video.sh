#!/bin/bash
# Turns the dictation frames from `Utter --snapshot <dir>` (<dir>/frames/frame-000.png …,
# 30 fps) into a looping GIF for the README and an MP4 for the portfolio.
#
#   swift build && .build/debug/Utter --snapshot /tmp/utter-snaps
#   ./scripts/make-demo-video.sh /tmp/utter-snaps/frames docs/images
#
# Needs ffmpeg (brew install ffmpeg). Writes <out>/demo.gif and <out>/demo.mp4.
set -euo pipefail

FRAMES="${1:?usage: make-demo-video.sh <frames-dir> <out-dir>}"
OUT="${2:?usage: make-demo-video.sh <frames-dir> <out-dir>}"
mkdir -p "$OUT"

# GIF: 810 px wide, one palette built from every frame so the orb's colours stay clean.
ffmpeg -loglevel error -y -framerate 30 -i "$FRAMES/frame-%03d.png" \
  -vf "scale=810:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a" \
  -loop 0 "$OUT/demo.gif"

# MP4: H.264 that plays muted and inline in every browser.
ffmpeg -loglevel error -y -framerate 30 -i "$FRAMES/frame-%03d.png" \
  -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow -movflags +faststart -an "$OUT/demo.mp4"

ls -lh "$OUT/demo.gif" "$OUT/demo.mp4"
