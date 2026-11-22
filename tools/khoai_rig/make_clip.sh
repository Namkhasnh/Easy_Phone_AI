#!/bin/bash
# AI clip (mp4 on a plain grey background) → transparent HEVC .mov for the app (D-327). Free, runs on the Mac.
# Usage: make_clip.sh <input.mp4> <output.mov> <work_dir> [python]
set -euo pipefail
IN=$1; OUT=$2; WORK=$3; PY=${4:-python3}
HERE=$(cd "$(dirname "$0")" && pwd)
rm -rf "$WORK"; mkdir -p "$WORK/frames" "$WORK/matte"
ffmpeg -loglevel error -y -i "$IN" -vf "scale=720:1280" "$WORK/frames/f%03d.png"
[ -x "$WORK/../mattebin" ] || swiftc -O "$HERE/matte.swift" -o "$WORK/../mattebin"
"$WORK/../mattebin" "$WORK/frames" "$WORK/matte" >/dev/null
"$PY" -I "$HERE/clean.py" "$WORK/matte" "$WORK/frames" "$WORK/clean" 600
ffmpeg -loglevel error -y -framerate 24 -i "$WORK/clean/p%03d.png" -c:v hevc_videotoolbox -alpha_quality 0.9 \
  -b:v 1200k -tag:v hvc1 -pix_fmt bgra -an "$OUT"
