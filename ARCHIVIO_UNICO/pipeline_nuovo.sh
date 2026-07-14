#!/usr/bin/env bash
# Pipeline completa -> sottocartella NUOVO_v2/
set -euo pipefail
cd "$(dirname "$0")/.."
chmod +x ARCHIVIO_UNICO/*.sh

OUT="Audio e Video Originali con sottotitoli/NUOVO_v2"

echo "========== FASE 0: Intro condivise =========="
bash ARCHIVIO_UNICO/genera_intro.sh

echo "========== FASE 1: SRT in NUOVO_v2/ =========="
python3 ARCHIVIO_UNICO/genera_nuovo.py

echo "========== FASE 2: Video =========="
MAX_LINES=7 bash ARCHIVIO_UNICO/genera_video.sh "$OUT"

echo "========== FASE 3: Intro =========="
bash ARCHIVIO_UNICO/aggiungi_intro.sh "$OUT" ARCHIVIO_UNICO/intro

echo "========== FATTO: $OUT/ =========="
