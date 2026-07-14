#!/usr/bin/env bash
# Genera video 240x320 con sottotitoli (equivalente Linux di genera-video.ps1)
set -euo pipefail

ROOT="${1:-.}"
WIDTH=240
HEIGHT=320
FPS=25
MAX_LINE=16

wrap_text() {
  python3 - "$MAX_LINE" <<'PY' "$1"
import re, sys
text = sys.argv[1]
max_len = int(sys.argv[2])
clean = re.sub(r"\s+", " ", text).strip()
if not clean:
    print("")
    raise SystemExit
words = clean.split()
lines, cur = [], ""
for w in words:
    if not cur:
        cur = w
        continue
    cand = f"{cur} {w}"
    if len(cand) <= max_len:
        cur = cand
    else:
        lines.append(cur)
        cur = w
if cur:
    lines.append(cur)
print("\\N".join(lines))
PY
}

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
    text = " ".join(lines[2:])
    clean = re.sub(r"\s+", " ", text).strip()
    wrapped = []
    cur = ""
    for w in clean.split():
        if not cur:
            cur = w
            continue
        cand = f"{cur} {w}"
        if len(cand) <= 16:
            cur = cand
        else:
            wrapped.append(cur)
            cur = w
    if cur:
        wrapped.append(cur)
    styled = "{\\an5}" + "\\N".join(wrapped)
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
  [[ -f "$srt" ]] || { echo "Salto $base: SRT mancante $srt"; continue; }
  mkdir -p "$srt_dir"
  styled="$srt_dir/${stem}__styled_tmp.srt"
  make_styled_srt "$srt" "$styled"
  out="$dir/${stem}.mp4"
  dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio" | tr -d '\r')
  echo "Genero $out"
  (
    cd "$dir"
    ffmpeg -nostdin -y -hide_banner -loglevel error \
      -f lavfi -i "color=c=black:s=${WIDTH}x${HEIGHT}:r=${FPS}" \
      -i "$base" \
      -t "$dur" \
      -vf "subtitles=srt/${stem}__styled_tmp.srt:charenc=UTF-8:force_style='FontName=Arial,FontSize=30,PrimaryColour=&HFFFFFF&,OutlineColour=&H000000&,BorderStyle=1,Outline=3,Shadow=0,Alignment=5,WrapStyle=0,MarginL=2,MarginR=2,MarginV=0'" \
      -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r "$FPS" -an \
      "$(basename "$out")"
  )
  rm -f "$styled"
done < <(find "$ROOT" -type f \( -iname '*.mp3' -o -iname '*.wav' -o -iname '*.m4a' \) -print0)

echo "Completato genera_video."
