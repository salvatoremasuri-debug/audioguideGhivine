#!/usr/bin/env bash
# Pipeline completa -> sottocartella NUOVO/
set -euo pipefail
cd "$(dirname "$0")/.."
chmod +x ARCHIVIO_UNICO/*.sh

echo "========== FASE 1: SRT in NUOVO/ =========="
python3 ARCHIVIO_UNICO/genera_nuovo.py

echo "========== FASE 2: Video =========="
bash ARCHIVIO_UNICO/genera_video.sh "Audio e Video Originali con sottotitoli/NUOVO"

echo "========== FASE 3: Intro =========="
bash ARCHIVIO_UNICO/aggiungi_intro.sh "Audio e Video Originali con sottotitoli/NUOVO" ARCHIVIO_UNICO/intro

echo "========== FATTO: Audio e Video Originali con sottotitoli/NUOVO/ =========="
