#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-Audio e Video Originali con sottotitoli/NUOVO_v2}"
INTRO_DIR="${2:-ARCHIVIO_UNICO/intro}"
LANG="${3:-}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for lang_dir in "$ROOT"/*/; do
  [[ -d "$lang_dir" ]] || continue
  lang=$(basename "$lang_dir")
  [[ "$lang" == "file" ]] && continue
  [[ -n "$LANG" && "$lang" != "$LANG" ]] && continue

  for video in "$lang_dir"*.mp4; do
    [[ -f "$video" ]] || continue
    base=$(basename "$video" .mp4)
    [[ "$base" =~ ^[0-9]{4}$ ]] || continue

    intro="$INTRO_DIR/${base}intro.mp4"
    [[ -f "$intro" ]] || { echo "Salto $lang/$base: intro mancante"; continue; }

    silence=2
    [[ "$base" == "0001" ]] && silence=5

    list="$tmp/${lang}_${base}_v.txt"
    printf "file '%s'\nfile '%s'\n" "$(realpath "$intro")" "$(realpath "$video")" > "$list"
    ffmpeg -nostdin -y -hide_banner -loglevel error -f concat -safe 0 -i "$list" \
      -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 -an \
      "$tmp/${lang}_${base}_out.mp4"
    mv "$tmp/${lang}_${base}_out.mp4" "$video"

    audio="$lang_dir${base}.mp3"
    if [[ -f "$audio" ]]; then
      ffmpeg -nostdin -y -hide_banner -loglevel error \
        -f lavfi -t "$silence" -i "anullsrc=r=44100:cl=mono" \
        -i "$audio" \
        -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1[a]" -map "[a]" -c:a libmp3lame \
        "$tmp/${lang}_${base}_out.mp3"
      mv "$tmp/${lang}_${base}_out.mp3" "$audio"
    fi

    echo "OK $lang/$base"
  done
done

echo "Intro applicate in $ROOT"
