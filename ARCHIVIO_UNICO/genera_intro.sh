#!/usr/bin/env bash
# Clip intro condivise 0001..0008 (uguali per tutte le lingue)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INTRO_DIR="${1:-$ROOT/ARCHIVIO_UNICO/intro}"
LOGO="${2:-$ROOT/Audio e Video Originali con sottotitoli/file/logo.jpg}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$INTRO_DIR"
[[ -f "$LOGO" ]] || LOGO="$ROOT/ARCHIVIO_UNICO/file/logo.jpg"
[[ -f "$LOGO" ]] || { echo "Logo non trovato"; exit 1; }

FONT=""
for f in /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf \
         /usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf; do
  [[ -f "$f" ]] && FONT="$f" && break
done
[[ -n "$FONT" ]] || { echo "Font bold non trovato"; exit 1; }
FONT_ESC="${FONT//:/\\:}"

number_clip() {
  local num="$1" dur="$2" out="$3"
  ffmpeg -nostdin -y -hide_banner -loglevel error \
    -f lavfi -i "color=c=black:s=240x320:r=25:d=$dur" \
    -f lavfi -i "color=c=0x2FBF71:s=170x170:r=25:d=$dur" \
    -filter_complex "[1:v]format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lte((X-W/2)^2+(Y-H/2)^2,(W/2-2)^2),255,0)'[ball];[0:v][ball]overlay=(W-w)/2:(H-h)/2,drawtext=fontfile='$FONT_ESC':text='$num':fontcolor=black:fontsize=98:borderw=2:bordercolor=black:x=(w-text_w)/2:y=(h-text_h)/2-2,fade=t=in:st=0:d=0.35,fade=t=out:st=$(python3 -c "print($dur-0.35)"):d=0.35" \
    -an -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 "$out"
}

logo_clip() {
  local out="$1"
  ffmpeg -nostdin -y -hide_banner -loglevel error \
    -loop 1 -i "$LOGO" \
    -f lavfi -i "color=c=black:s=240x320:r=25:d=3" \
    -filter_complex "[0:v]scale=240:320:force_original_aspect_ratio=decrease[lg];[1:v][lg]overlay=(W-w)/2:(H-h)/2,fade=t=in:st=0:d=0.4,fade=t=out:st=2.6:d=0.4" \
    -t 3 -an -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 "$out"
}

for i in $(seq 1 8); do
  base=$(printf '%04d' "$i")
  intro_out="$INTRO_DIR/${base}intro.mp4"
  if [[ -f "$intro_out" ]]; then
    echo "Esiste già $intro_out"
    continue
  fi
  if [[ "$i" -eq 1 ]]; then
    logo_clip "$TMP/0001_logo.mp4"
    number_clip 1 2 "$TMP/0001_num.mp4"
    printf "file '%s'\nfile '%s'\n" "$TMP/0001_logo.mp4" "$TMP/0001_num.mp4" > "$TMP/0001_list.txt"
    ffmpeg -nostdin -y -hide_banner -loglevel error -f concat -safe 0 -i "$TMP/0001_list.txt" \
      -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 -an "$intro_out"
  else
    number_clip "$i" 2 "$intro_out"
  fi
  echo "Creato $intro_out"
done

echo "Intro condivise in $INTRO_DIR"
