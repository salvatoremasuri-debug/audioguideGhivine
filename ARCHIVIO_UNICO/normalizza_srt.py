import argparse
from pathlib import Path
import re


TIME_RE = re.compile(r"(\d{2}):(\d{2}):(\d{2}),(\d{3})")


def to_ms(ts: str) -> int:
    m = TIME_RE.fullmatch(ts.strip())
    if not m:
        raise ValueError(f"Invalid timestamp: {ts}")
    hh, mm, ss, ms = map(int, m.groups())
    return ((hh * 60 + mm) * 60 + ss) * 1000 + ms


def from_ms(total: int) -> str:
    if total < 0:
        total = 0
    ms = total % 1000
    total //= 1000
    ss = total % 60
    total //= 60
    mm = total % 60
    hh = total // 60
    return f"{hh:02d}:{mm:02d}:{ss:02d},{ms:03d}"


def chunk_text(text: str, max_chars: int) -> list[str]:
    words = re.sub(r"\s+", " ", text).strip().split(" ")
    words = [w for w in words if w]
    if not words:
        return [""]

    chunks: list[str] = []
    current = words[0]
    for w in words[1:]:
        candidate = f"{current} {w}"
        if len(candidate) <= max_chars:
            current = candidate
        else:
            chunks.append(current)
            current = w
    chunks.append(current)
    return chunks


def parse_srt(raw: str):
    blocks = re.split(r"\r?\n\r?\n+", raw.strip())
    cues = []
    for b in blocks:
        lines = [ln for ln in re.split(r"\r?\n", b) if ln.strip() != ""]
        if len(lines) < 3:
            continue
        timing = lines[1]
        if " --> " not in timing:
            continue
        start, end = timing.split(" --> ", 1)
        text = " ".join(lines[2:]).strip()
        cues.append((start.strip(), end.strip(), text))
    return cues


def build_srt(cues):
    out = []
    for idx, (start, end, text) in enumerate(cues, start=1):
        out.append(str(idx))
        out.append(f"{start} --> {end}")
        out.append(text)
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def process_file(path: Path, max_chars: int) -> bool:
    raw = path.read_text(encoding="utf-8", errors="replace")
    cues = parse_srt(raw)
    new_cues = []
    changed = False

    for start, end, text in cues:
        cleaned = re.sub(r"\s+", " ", text).strip()
        if len(cleaned) <= max_chars:
            new_cues.append((start, end, cleaned))
            continue

        parts = chunk_text(cleaned, max_chars)
        if len(parts) <= 1:
            new_cues.append((start, end, cleaned))
            continue

        changed = True
        start_ms = to_ms(start)
        end_ms = to_ms(end)
        dur = max(1, end_ms - start_ms)
        total_chars = sum(max(1, len(p)) for p in parts)

        cursor = start_ms
        for i, part in enumerate(parts):
            w = max(1, len(part))
            if i == len(parts) - 1:
                part_end = end_ms
            else:
                part_dur = max(1, int(round(dur * (w / total_chars))))
                part_end = min(end_ms - (len(parts) - i - 1), cursor + part_dur)
            new_cues.append((from_ms(cursor), from_ms(part_end), part))
            cursor = part_end

    new_raw = build_srt(new_cues)
    if changed and new_raw != raw:
        path.write_text(new_raw, encoding="utf-8")
        return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--max-chars", type=int, default=90)
    ap.add_argument("--out-modified", required=True)
    args = ap.parse_args()

    root = Path(args.root)
    srt_files = sorted(root.glob("*/srt/*.srt"))
    modified = []
    for srt in srt_files:
        if process_file(srt, args.max_chars):
            modified.append(srt)

    out = Path(args.out_modified)
    out.write_text("\n".join(str(p) for p in modified) + ("\n" if modified else ""), encoding="utf-8")
    print(f"Checked {len(srt_files)} files; modified {len(modified)}.")


if __name__ == "__main__":
    main()
