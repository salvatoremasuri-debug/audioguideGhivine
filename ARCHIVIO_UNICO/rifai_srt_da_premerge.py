"""Ricostruisce SRT: tempi dal pre_merge, testo originale, split a meta' se troppo lungo."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from verifica_e_correggi_srt import (
    align_words_to_timed_cues,
    build_srt,
    enforce_cue_splits,
)


def parse_premerge_srt(raw: str) -> list[tuple[str, str, str]]:
    cues: list[tuple[str, str, str]] = []
    lines = raw.splitlines()
    i = 0
    while i < len(lines):
        while i < len(lines) and not lines[i].strip():
            i += 1
        if i >= len(lines):
            break

        if re.fullmatch(r"\d+", lines[i].strip()):
            i += 1
            if i >= len(lines):
                break

        timing = lines[i].strip()
        if " --> " not in timing:
            i += 1
            continue

        start, end = timing.split(" --> ", 1)
        i += 1
        text_lines: list[str] = []
        while i < len(lines):
            nxt = lines[i].strip()
            if not nxt:
                break
            if " --> " in nxt:
                break
            if re.fullmatch(r"\d+", nxt):
                break
            text_lines.append(nxt)
            i += 1

        text = re.sub(r"\s+", " ", " ".join(text_lines)).strip()
        cues.append((start.strip(), end.strip(), text))

    return cues


def rebuild_from_premerge(
    premerge_cues: list[tuple[str, str, str]],
    original_text: str,
    max_chars: int,
    max_line_chars: int,
    max_lines: int,
    max_word_chars: int,
) -> list[tuple[str, str, str]]:
    if not premerge_cues:
        return []

    aligned = align_words_to_timed_cues(
        premerge_cues,
        original_text,
        max_line_chars,
        max_word_chars,
        weights=[len(re.sub(r"\s+", " ", t).split()) for _, _, t in premerge_cues],
    )
    return enforce_cue_splits(
        aligned,
        max_chars,
        max_line_chars,
        max_lines,
        max_word_chars,
    )


def lang_code(folder: str) -> str:
    return {"SP": "ES"}.get(folder.upper(), folder.upper())


def txt_path(archivio: Path, folder: str, num: str) -> Path:
    code = lang_code(folder)
    return archivio / "testi_originali" / code / f"{int(num):02d}_{code}.txt"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--archivio", default="ARCHIVIO_UNICO")
    ap.add_argument("--output-root", default="Audio e Video Originali con sottotitoli")
    ap.add_argument("--timing", action="append", default=[], metavar="LANG:NUM:PATH")
    ap.add_argument("--max-chars", type=int, default=45)
    ap.add_argument("--max-line-chars", type=int, default=16)
    ap.add_argument("--max-word-chars", type=int, default=14)
    ap.add_argument("--max-lines", type=int, default=3)
    args = ap.parse_args()

    archivio = Path(args.archivio)
    output_root = Path(args.output_root)
    fixed: list[str] = []

    for spec in args.timing:
        folder, num, rel = spec.split(":", 2)
        timing_path = archivio / rel if not Path(rel).is_absolute() else Path(rel)
        out_path = output_root / folder / "srt" / f"{num}.srt"
        txt = txt_path(archivio, folder, num)
        if not timing_path.exists():
            raise FileNotFoundError(timing_path)
        if not txt.exists():
            raise FileNotFoundError(txt)

        premerge = parse_premerge_srt(timing_path.read_text(encoding="utf-8", errors="replace"))
        original = txt.read_text(encoding="utf-8", errors="replace")
        rebuilt = rebuild_from_premerge(
            premerge,
            original,
            args.max_chars,
            args.max_line_chars,
            args.max_lines,
            args.max_word_chars,
        )
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(build_srt(rebuilt), encoding="utf-8")
        fixed.append(out_path.as_posix())
        print(f"OK {out_path} ({len(rebuilt)} cue)")

    log = archivio / "fixed_premerge.txt"
    log.write_text("\n".join(fixed) + ("\n" if fixed else ""), encoding="utf-8")
    print(f"Completato: {len(fixed)} file.")


if __name__ == "__main__":
    main()
