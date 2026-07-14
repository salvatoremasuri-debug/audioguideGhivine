import argparse
from pathlib import Path
import re

from verifica_e_correggi_srt import (
    build_srt,
    cue_too_long,
    enforce_cue_splits,
    format_cue_text,
    parse_srt,
    split_cue_halve,
)


def process_file(
    path: Path,
    max_chars: int,
    max_line_chars: int,
    max_lines: int,
    max_word_chars: int,
) -> bool:
    raw = path.read_text(encoding="utf-8", errors="replace")
    cues = parse_srt(raw)
    wrapped = enforce_cue_splits(cues, max_chars, max_line_chars, max_lines, max_word_chars)
    new_raw = build_srt(wrapped)
    if new_raw != raw:
        path.write_text(new_raw, encoding="utf-8")
        return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--max-chars", type=int, default=50)
    ap.add_argument("--max-line-chars", type=int, default=16)
    ap.add_argument("--max-word-chars", type=int, default=14)
    ap.add_argument("--max-lines", type=int, default=4)
    ap.add_argument("--out-modified", required=True)
    args = ap.parse_args()

    root = Path(args.root)
    srt_files = sorted(root.glob("*/srt/*.srt"))
    modified = []
    for srt in srt_files:
        if srt.stem.endswith("__styled_tmp"):
            continue
        if process_file(
            srt,
            args.max_chars,
            args.max_line_chars,
            args.max_lines,
            args.max_word_chars,
        ):
            modified.append(srt)

    out = Path(args.out_modified)
    out.write_text("\n".join(str(p) for p in modified) + ("\n" if modified else ""), encoding="utf-8")
    print(f"Checked {len(srt_files)} files; modified {len(modified)}.")


if __name__ == "__main__":
    main()
