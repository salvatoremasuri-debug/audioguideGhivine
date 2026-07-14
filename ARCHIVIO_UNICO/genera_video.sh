#!/usr/bin/env bash
# Video 240x320 da SRT: durata dall'ultimo cue, senza audio sorgente
set -euo pipefail

ROOT="${1:-Audio e Video Originali con sottotitoli/NUOVO_v2}"
WIDTH=240
HEIGHT=320
FPS=25
FONT_SIZE=26
MARGIN_V=18
MAX_LINES=7

make_styled_srt() {
  local src="$1" dst="$2"
  python3 - "$src" "$dst" <<'PY'
import os, re, sys
from pathlib import Path

src, dst = sys.argv[1], sys.argv[2]
max_lines = int(os.environ.get("MAX_LINES", "7"))
raw = Path(src).read_text(encoding="utf-8", errors="replace")
blocks = re.split(r"\n\s*\n", raw.strip())
out = []
for b in blocks:
    lines = [ln for ln in b.splitlines() if ln.strip()]
    if len(lines) < 3:
        continue
    idx, timing = lines[0], lines[1]
    text_lines = [ln.strip() for ln in lines[2:] if ln.strip()]
    if len(text_lines) > max_lines:
        text_lines = text_lines[:max_lines]
    styled = "{\\an5}" + "\\N".join(text_lines)
    out.extend([idx, timing, styled, ""])
Path(dst).write_text("\n".join(out).rstrip() + "\n", encoding="utf-8-sig")
PY
}

srt_duration() {
  python3 - "$1" <<'PY'
import re, sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
ends = []
for m in re.finditer(r"-->\s*(\d{2}):(\d{2}):(\d{2}),(\d{3})", raw):
    h, mi, s, ms = map(int, m.groups())
    ends.append((h * 3600 + mi * 60 + s) * 1000 + ms)
print(f"{max(ends) / 1000:.3f}" if ends else "0")
PY
}

while IFS= read -r -d '' srt; do
  [[ "$srt" == *__styled_tmp* ]] && continue
  stem=$(basename "$srt" .srt)
  [[ "$stem" =~ ^[0-9]{4}$ ]] || continue

  lang_dir=$(dirname "$(dirname "$srt")")
  styled="$(dirname "$srt")/${stem}__styled_tmp.srt"
  make_styled_srt "$srt" "$styled"
  dur=$(srt_duration "$srt")
  [[ "$dur" != "0" && "$dur" != "0.000" ]] || { echo "Salto $stem: durata SRT zero"; rm -f "$styled"; continue; }

  echo "Genero $lang_dir/${stem}.mp4 (${dur}s)"
  (
    cd "$lang_dir"
    ffmpeg -nostdin -y -hide_banner -loglevel error \
      -f lavfi -i "color=c=black:s=${WIDTH}x${HEIGHT}:r=${FPS}" \
      -t "$dur" \
      -vf "subtitles=srt/${stem}__styled_tmp.srt:charenc=UTF-8:force_style='FontName=Arial,FontSize=${FONT_SIZE},PrimaryColour=&HFFFFFF&,OutlineColour=&H000000&,BorderStyle=1,Outline=2,Shadow=0,Alignment=5,WrapStyle=0,MarginL=4,MarginR=4,MarginV=${MARGIN_V}'" \
      -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r "$FPS" -an \
      "${stem}.mp4"
  )
  rm -f "$styled"
done < <(find "$ROOT" -path '*/srt/*.srt' -print0)

echo "Completato genera_video."
