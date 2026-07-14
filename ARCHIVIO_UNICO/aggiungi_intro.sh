#!/usr/bin/env bash
# Concatena intro + video/audio finale (equivalente Linux)
set -euo pipefail

ROOT="${1:-Audio e Video Originali con sottotitoli}"
INTRO_DIR="${2:-ARCHIVIO_UNICO/intro}"
LANG="${3:-IT}"
FILTER="${4:-}"

lang_dir="$ROOT/$LANG"
intro_dir="$INTRO_DIR"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for audio in "$lang_dir"/*.mp3; do
  [[ -f "$audio" ]] || continue
  base=$(basename "$audio" .mp3)
  [[ "$base" =~ ^[0-9]{4}$ ]] || continue
  if [[ -n "$FILTER" && "$base" != "$FILTER" ]]; then
    continue
  fi

  video="$lang_dir/${base}.mp4"
  intro="$intro_dir/${base}intro.mp4"
  [[ -f "$video" ]] || { echo "Salto $base: video mancante"; continue; }
  [[ -f "$intro" ]] || { echo "Salto $base: intro mancante $intro"; continue; }

  silence=2
  [[ "$base" == "0001" ]] && silence=5

  list="$tmp/${base}_v.txt"
  printf "file '%s'\nfile '%s'\n" "$(realpath "$intro")" "$(realpath "$video")" > "$list"
  ffmpeg -nostdin -y -hide_banner -loglevel error -f concat -safe 0 -i "$list" \
    -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 -an \
    "$tmp/${base}_out.mp4"
  mv "$tmp/${base}_out.mp4" "$video"

  ffmpeg -nostdin -y -hide_banner -loglevel error \
    -f lavfi -t "$silence" -i "anullsrc=r=44100:cl=mono" \
    -i "$audio" \
    -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1[a]" -map "[a]" -c:a libmp3lame \
    "$tmp/${base}_out.mp3"
  mv "$tmp/${base}_out.mp3" "$audio"

  echo "OK $LANG/$base (intro ${silence}s)"
done

echo "Intro applicate a $LANG"
