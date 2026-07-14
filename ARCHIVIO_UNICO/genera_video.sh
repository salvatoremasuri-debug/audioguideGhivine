#!/usr/bin/env bash
# Video 240x320: mantiene le righe SRT, font ridotto, margini verticali
set -euo pipefail

ROOT="${1:-Audio e Video Originali con sottotitoli/NUOVO}"
WIDTH=240
HEIGHT=320
FPS=25
FONT_SIZE=24
MARGIN_V=30

make_styled_srt() {
  local src="$1" dst="$2"
  python3 - "$src" "$dst" <<'PY'
import re, sys
from pathlib import Path

src, dst = sys.argv[1], sys.argv[2]
raw = Path(src).read_text(encoding="utf-8", errors="replace")
blocks = re.split(r"\n\s*\n", raw.strip())
out = []
for b in blocks:
    lines = [ln for ln in b.splitlines() if ln.strip()]
    if len(lines) < 3:
        continue
    idx, timing = lines[0], lines[1]
    text_lines = [ln.strip() for ln in lines[2:] if ln.strip()]
    if len(text_lines) > 3:
        text_lines = text_lines[:3]
    styled = "{\\an5}" + "\\N".join(text_lines)
    out.extend([idx, timing, styled, ""])
Path(dst).write_text("\n".join(out).rstrip() + "\n", encoding="utf-8-sig")
PY
}

while IFS= read -r -d '' audio; do
  dir=$(dirname "$audio")
  base=$(basename "$audio")
  stem="${base%.*}"
  srt_dir="$dir/srt"
  srt="$srt_dir/${stem}.srt"
  [[ -f "$srt" ]] || { echo "Salto $base: SRT mancante"; continue; }
  styled="$srt_dir/${stem}__styled_tmp.srt"
  make_styled_srt "$srt" "$styled"
  dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio" | tr -d '\r')
  echo "Genero $dir/${stem}.mp4"
  (
    cd "$dir"
    ffmpeg -nostdin -y -hide_banner -loglevel error \
      -f lavfi -i "color=c=black:s=${WIDTH}x${HEIGHT}:r=${FPS}" \
      -i "$base" \
      -t "$dur" \
      -vf "subtitles=srt/${stem}__styled_tmp.srt:charenc=UTF-8:force_style='FontName=Arial,FontSize=${FONT_SIZE},PrimaryColour=&HFFFFFF&,OutlineColour=&H000000&,BorderStyle=1,Outline=2,Shadow=0,Alignment=5,WrapStyle=0,MarginL=4,MarginR=4,MarginV=${MARGIN_V}'" \
      -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r "$FPS" -an \
      "${stem}.mp4"
  )
  rm -f "$styled"
done < <(find "$ROOT" -type f \( -iname '*.mp3' -o -iname '*.wav' \) -print0)

echo "Completato genera_video NUOVO."
