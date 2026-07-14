#!/usr/bin/env python3
"""Corregge SRT: pre_merge per casi speciali, split a meta' per tutti gli altri."""

from __future__ import annotations

import difflib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARCHIVIO = ROOT / "ARCHIVIO_UNICO"
OUTPUT = ROOT / "Audio e Video Originali con sottotitoli"

PREMERGE_MAP = {
    ("IT", "0002"): "IT_ORIGINALI/srt/0002.pre_merge_20260424_165438.srt",
    ("IT", "0008"): "IT_ORIGINALI/srt/0008_formato_ideale_tempi_da_correggere.srt",
    ("EN", "0008"): "EN_ORIGINALI/srt/0008.pre_merge_20260424_165438.srt",
    ("FR", "0008"): "FR_ORIGINALI/srt/0008.pre_merge_20260424_165438.srt",
    ("SP", "0008"): "SP_ORIGINALI/srt/0008.pre_merge_20260424_165438.srt",
}

MAX_CHARS = 50
MAX_LINE_CHARS = 16
MAX_WORD_CHARS = 14
MAX_LINES = 4


def run_premerge() -> None:
    specs = []
    for (folder, num), rel in PREMERGE_MAP.items():
        specs.append(f"{folder}:{num}:{rel}")

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


def patch_output_folders() -> None:
    import verifica_e_correggi_srt as vec

    folder_by_code = {"IT": "IT", "EN": "EN", "FR": "FR", "SP": "SP", "DE": "DE"}
    fixed: list[str] = []

    for code, folder in folder_by_code.items():
        srt_dir = OUTPUT / folder / "srt"
        if not srt_dir.exists():
            continue
        for srt_path in sorted(srt_dir.glob("*.srt")):
            if srt_path.stem.endswith("__styled_tmp"):
                continue
            if (folder, srt_path.stem) in PREMERGE_MAP:
                continue

            txt_code = "ES" if code == "SP" else code
            txt_path = ARCHIVIO / "testi_originali" / txt_code / f"{int(srt_path.stem):02d}_{txt_code}.txt"
            if not txt_path.exists():
                continue

            orig_text = vec.strip_leading_titles(txt_path.read_text(encoding="utf-8", errors="replace"))
            raw = srt_path.read_text(encoding="utf-8", errors="replace")
            cues = vec.parse_srt(raw)
            if not cues:
                continue

            srt_text = " ".join(t for _, _, t in cues)
            ratio = difflib.SequenceMatcher(None, vec.normalize(orig_text), vec.normalize(srt_text)).ratio()
            too_long = any(
                vec.cue_too_long(t, MAX_CHARS, MAX_LINE_CHARS, MAX_LINES) for _, _, t in cues
            )

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
            fixed.append(srt_path.relative_to(OUTPUT).as_posix())
            print(f"verifica: {srt_path.name} ({folder}) -> {len(wrapped)} cue")

    (ARCHIVIO / "fixed_verifica_output.txt").write_text(
        "\n".join(fixed) + ("\n" if fixed else ""),
        encoding="utf-8",
    )


def run_normalizza() -> None:
    cmd = [
        sys.executable,
        str(ARCHIVIO / "normalizza_srt.py"),
        "--root",
        str(OUTPUT),
        "--max-chars",
        str(MAX_CHARS),
        "--max-lines",
        str(MAX_LINES),
        "--out-modified",
        str(ARCHIVIO / "modified_output_srt.txt"),
    ]
    subprocess.check_call(cmd, cwd=ROOT)


def main() -> None:
    sys.path.insert(0, str(ARCHIVIO))
    print("=== 1/3 Rifacimento da pre_merge (tempi invariati) ===")
    run_premerge()
    print("=== 2/3 Allineamento testo + split a meta' ===")
    patch_output_folders()
    print("Correzioni completate.")


if __name__ == "__main__":
    main()
