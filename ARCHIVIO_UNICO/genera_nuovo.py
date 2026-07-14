#!/usr/bin/env python3
"""Genera SRT e media nella sottocartella NUOVO (senza toccare gli originali)."""

from __future__ import annotations

import difflib
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARCHIVIO = ROOT / "ARCHIVIO_UNICO"
SOURCE = ROOT / "Audio e Video Originali con sottotitoli"
OUTPUT = SOURCE / "NUOVO"

PREMERGE_MAP = {
    ("IT", "0002"): "IT_ORIGINALI/srt/0002.pre_merge_20260424_165438.srt",
    ("IT", "0008"): "IT_ORIGINALI/srt/0008_formato_ideale_tempi_da_correggere.srt",
    ("EN", "0008"): "EN_ORIGINALI/srt/0008.pre_merge_20260424_165438.srt",
    ("FR", "0008"): "FR_ORIGINALI/srt/0008.pre_merge_20260424_165438.srt",
    ("SP", "0008"): "SP_ORIGINALI/srt/0008.pre_merge_20260424_165438.srt",
}

# Max 3 righe x 16 caratteri: evita overflow su schermo 240x320
MAX_CHARS = 45
MAX_LINE_CHARS = 16
MAX_WORD_CHARS = 14
MAX_LINES = 3


def strip_intro_audio(src: Path, dst: Path, stem: str) -> None:
    skip = 5.0 if stem == "0001" else 2.0
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.check_call(
        [
            "ffmpeg",
            "-nostdin",
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-ss",
            str(skip),
            "-i",
            str(src),
            "-acodec",
            "libmp3lame",
            str(dst),
        ]
    )


def prepare_audio() -> None:
    for lang_dir in sorted(SOURCE.iterdir()):
        if not lang_dir.is_dir() or lang_dir.name in {"NUOVO", "file"}:
            continue
        lang = lang_dir.name
        out_lang = OUTPUT / lang
        out_lang.mkdir(parents=True, exist_ok=True)
        for mp3 in sorted(lang_dir.glob("*.mp3")):
            strip_intro_audio(mp3, out_lang / mp3.name, mp3.stem)
            print(f"audio: {lang}/{mp3.name}")


def seed_srt_from_source() -> None:
    """Copia gli SRT sorgente come base tempi (poi vengono riscritti)."""
    for lang_dir in sorted(SOURCE.iterdir()):
        if not lang_dir.is_dir() or lang_dir.name in {"NUOVO", "file"}:
            continue
        src_srt = lang_dir / "srt"
        if not src_srt.exists():
            continue
        dst_srt = OUTPUT / lang_dir.name / "srt"
        if dst_srt.exists():
            shutil.rmtree(dst_srt)
        shutil.copytree(src_srt, dst_srt)
        print(f"srt seed: {lang_dir.name}")


def run_premerge() -> None:
    specs = [f"{folder}:{num}:{rel}" for (folder, num), rel in PREMERGE_MAP.items()]
    cmd = [
        sys.executable,
        str(ARCHIVIO / "rifai_srt_da_premerge.py"),
        "--archivio",
        str(ARCHIVIO),
        "--output-root",
        str(OUTPUT),
        "--max-chars",
        str(MAX_CHARS),
        "--max-lines",
        str(MAX_LINES),
    ]
    for spec in specs:
        cmd.extend(["--timing", spec])
    subprocess.check_call(cmd, cwd=ROOT)


def patch_srt() -> None:
    import verifica_e_correggi_srt as vec

    for lang_dir in sorted(OUTPUT.iterdir()):
        if not lang_dir.is_dir():
            continue
        lang = lang_dir.name
        srt_dir = lang_dir / "srt"
        if not srt_dir.exists():
            continue
        code = "ES" if lang == "SP" else lang

        for srt_path in sorted(srt_dir.glob("*.srt")):
            if srt_path.stem.endswith("__styled_tmp"):
                continue
            if (lang, srt_path.stem) in PREMERGE_MAP:
                continue

            txt_path = ARCHIVIO / "testi_originali" / code / f"{int(srt_path.stem):02d}_{code}.txt"
            if not txt_path.exists():
                continue

            orig_text = vec.strip_leading_titles(txt_path.read_text(encoding="utf-8", errors="replace"))
            cues = vec.parse_srt(srt_path.read_text(encoding="utf-8", errors="replace"))
            if not cues:
                continue

            srt_text = " ".join(t for _, _, t in cues)
            ratio = difflib.SequenceMatcher(None, vec.normalize(orig_text), vec.normalize(srt_text)).ratio()
            too_long = any(vec.cue_too_long(t, MAX_CHARS, MAX_LINE_CHARS, MAX_LINES) for _, _, t in cues)
            if ratio >= 0.995 and not too_long:
                continue

            aligned = vec.align_words_to_timed_cues(
                cues,
                orig_text,
                MAX_LINE_CHARS,
                MAX_WORD_CHARS,
                weights=[len(re.sub(r"\s+", " ", t).split()) for _, _, t in cues],
            )
            wrapped = vec.enforce_cue_splits(
                aligned,
                MAX_CHARS,
                MAX_LINE_CHARS,
                MAX_LINES,
                MAX_WORD_CHARS,
            )
            srt_path.write_text(vec.build_srt(wrapped), encoding="utf-8")
            print(f"srt: {lang}/{srt_path.name} -> {len(wrapped)} cue")


def copy_assets() -> None:
    logo_src = SOURCE / "file" / "logo.jpg"
    if not logo_src.exists():
        logo_src = ARCHIVIO / "file" / "logo.jpg"
    dst = OUTPUT / "file"
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copy2(logo_src, dst / "logo.jpg")


def main() -> None:
    sys.path.insert(0, str(ARCHIVIO))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    print("=== 1. Prepara audio (senza intro) in NUOVO/ ===")
    prepare_audio()
    print("=== 2. Seed SRT ===")
    seed_srt_from_source()
    print("=== 3. Rifacimento pre_merge ===")
    run_premerge()
    print("=== 4. Correzione altri SRT ===")
    patch_srt()
    print("=== 5. Asset ===")
    copy_assets()
    print(f"Completato: {OUTPUT}")


if __name__ == "__main__":
    main()
