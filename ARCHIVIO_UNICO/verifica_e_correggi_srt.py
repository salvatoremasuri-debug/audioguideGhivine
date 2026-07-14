import argparse
import difflib
import re
from pathlib import Path


TIME_RE = re.compile(r"(\d{2}):(\d{2}):(\d{2}),(\d{3})")


def to_ms(ts: str) -> int:
    m = TIME_RE.fullmatch(ts.strip())
    if not m:
        raise ValueError(f"Bad timestamp: {ts}")
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


def normalize(s: str) -> str:
    s = s.lower()
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"[^\w\sàèéìíîïòóùúüçñäöß']", "", s, flags=re.UNICODE)
    return s


def parse_srt(raw: str):
    blocks = re.split(r"\r?\n\r?\n+", raw.strip())
    cues = []
    for b in blocks:
        lines = [ln for ln in re.split(r"\r?\n", b) if ln.strip()]
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


def split_long_word(word: str, max_word_chars: int):
    if len(word) <= max_word_chars:
        return [word]
    parts = []
    i = 0
    while i < len(word):
        take = max_word_chars
        if i + take < len(word):
            take = max(2, max_word_chars - 1)
            parts.append(word[i:i + take] + "-")
            i += take
        else:
            parts.append(word[i:i + max_word_chars])
            i += max_word_chars
    return parts


def strip_leading_titles(original_text: str) -> str:
    lines = [ln.strip() for ln in re.split(r"\r?\n", original_text)]
    lines = [ln for ln in lines if ln]
    while lines:
        ln = lines[0]
        if "AUDIO" in ln.upper() and all(ch not in ln for ch in ".!?"):
            lines = lines[1:]
            continue
        # Ese.: "2. ¿POR QUÉ ..." (spagnolo) — prima c'era solo [A-Z] e non toglieva la riga.
        if re.match(r"^\d+[\.\)]\s*¿", ln):
            lines = lines[1:]
            continue
        if re.match(r"^\d+[\.\)]\s*[A-ZÀ-ÖØ-Þ].*$", ln):
            lines = lines[1:]
            continue
        break
    body = "\n".join(lines).strip()
    return body if body else original_text


def _move_short_tail(line: str, next_token: str):
    words = line.split(" ")
    if len(words) <= 1:
        return line, next_token
    tail = words[-1]
    short_tail = len(tail) <= 2 or tail.lower() in {"di", "e", "a", "o", "il", "la", "lo", "un", "una", "è"}
    if not short_tail:
        return line, next_token
    new_line = " ".join(words[:-1]).strip()
    if not new_line:
        return line, next_token
    return new_line, f"{tail} {next_token}"


def build_lines(text: str, max_line_chars: int, max_word_chars: int):
    tokens = []
    for raw in [w for w in re.split(r"\s+", text.strip()) if w]:
        tokens.extend(split_long_word(raw, max_word_chars))

    lines = []
    current = ""
    for tok in tokens:
        if not current:
            current = tok
            continue
        cand = current + " " + tok
        if len(cand) <= max_line_chars:
            current = cand
        else:
            current, tok = _move_short_tail(current, tok)
            lines.append(current)
            current = tok
    if current:
        lines.append(current)
    return lines


def build_balanced_screens(lines, max_lines):
    if not lines:
        return []
    pages = (len(lines) + max_lines - 1) // max_lines
    base = len(lines) // pages
    rem = len(lines) % pages
    counts = [base + (1 if i < rem else 0) for i in range(pages)]

    screens = []
    idx = 0
    for cnt in counts:
        chunk = lines[idx:idx + cnt]
        idx += cnt
        screens.append(chunk)

    # Avoid one-line/one-word trailing pages when possible.
    if len(screens) >= 2:
        last_words = len(" ".join(screens[-1]).split())
        if len(screens[-1]) == 1 and last_words <= 2 and len(screens[-2]) > 2:
            screens[-1].insert(0, screens[-2].pop())

    # Avoid one-line screens with very short text ("è", "di visita:", etc.).
    i = 0
    while i < len(screens):
        words = len(" ".join(screens[i]).split())
        if len(screens[i]) == 1 and words <= 3:
            if i > 0 and len(screens[i - 1]) > 2:
                screens[i].insert(0, screens[i - 1].pop())
            elif i + 1 < len(screens):
                screens[i + 1].insert(0, screens[i][0])
                screens.pop(i)
                continue
        i += 1

    return ["\n".join(s) for s in screens if s]


def pack_screens_greedy(all_lines, max_lines: int, max_chars: int):
    """Raggruppa le righe in schermate: max N righe e max M caratteri (testo con spazi)."""
    if not all_lines:
        return []
    out = []
    current: list = []
    for ln in all_lines:
        if not current:
            current = [ln]
            continue
        trial = current + [ln]
        tlen = len(" ".join(trial))
        if len(trial) <= max_lines and tlen <= max_chars:
            current = trial
        else:
            out.append(current)
            current = [ln]
    if current:
        out.append(current)
    return out


def rebuild_from_original(cues, original_text, max_chars, max_line_chars, max_lines, max_word_chars):
    if not cues:
        return cues
    body = strip_leading_titles(original_text)
    cleaned = re.sub(r"\s+", " ", body).strip()
    if not cleaned:
        return cues

    lines = build_lines(cleaned, max_line_chars, max_word_chars)
    line_blocks = pack_screens_greedy(lines, max_lines, max_chars)
    chunks = ["\n".join(blk) for blk in line_blocks if blk]
    if not chunks:
        chunks = [cleaned[: max_chars].strip() or cleaned[:90]]

    start_ms = to_ms(cues[0][0])
    end_ms = to_ms(cues[-1][1])
    total_dur = max(1, end_ms - start_ms)
    total_chars = sum(max(1, len(c)) for c in chunks)

    new_cues = []
    cursor = start_ms
    for i, c in enumerate(chunks):
        w = max(1, len(c))
        if i == len(chunks) - 1:
            part_end = end_ms
        else:
            part_dur = max(1, int(round(total_dur * (w / total_chars))))
            part_end = min(end_ms - (len(chunks) - i - 1), cursor + part_dur)
        new_cues.append((from_ms(cursor), from_ms(part_end), c))
        cursor = part_end
    return new_cues


def file_number(stem: str) -> str:
    m = re.match(r"^(\d{4})", stem)
    if not m:
        raise ValueError(f"Cannot parse number from {stem}")
    return m.group(1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--max-chars", type=int, default=90)
    ap.add_argument("--max-line-chars", type=int, default=16)
    ap.add_argument("--max-word-chars", type=int, default=14)
    ap.add_argument("--max-lines", type=int, default=9)
    ap.add_argument("--ratio-threshold", type=float, default=0.995)
    ap.add_argument("--out-fixed", required=True)
    args = ap.parse_args()

    root = Path(args.root)
    original_root = root / "testi_originali"
    # Cartelle lingua: italiano, english, french, spanish, german (nomi a word)
    folder_by_code = {
        "IT": "italiano",
        "EN": "english",
        "FR": "french",
        "SP": "spanish",
        "DE": "german",
    }

    targets = []
    for code, folder in folder_by_code.items():
        for p in sorted((root / folder / "srt").glob("*.srt")):
            if p.stem.endswith("__styled_tmp"):
                continue
            targets.append((code, p))

    fixed = []
    for code, srt_path in targets:
        txt_code = "ES" if code == "SP" else code
        num = file_number(srt_path.stem)
        txt_num = f"{int(num):02d}"
        txt_path = original_root / txt_code / f"{txt_num}_{txt_code}.txt"
        if not txt_path.exists():
            continue

        orig_text_raw = txt_path.read_text(encoding="utf-8", errors="replace")
        orig_text = strip_leading_titles(orig_text_raw)
        raw = srt_path.read_text(encoding="utf-8", errors="replace")
        cues = parse_srt(raw)
        srt_text = " ".join(t for _, _, t in cues)

        ratio = difflib.SequenceMatcher(None, normalize(orig_text), normalize(srt_text)).ratio()
        too_long = any(
            len(re.sub(r"\s+", " ", t).strip()) > args.max_chars
            or any(len(ln) > args.max_line_chars for ln in re.split(r"\r?\n", t))
            or len([ln for ln in re.split(r"\r?\n", t) if ln.strip()]) > args.max_lines
            for _, _, t in cues
        )

        if ratio >= args.ratio_threshold and not too_long:
            continue

        wrapped = rebuild_from_original(
            cues,
            orig_text,
            args.max_chars,
            args.max_line_chars,
            args.max_lines,
            args.max_word_chars,
        )
        srt_path.write_text(build_srt(wrapped), encoding="utf-8")
        fixed.append(srt_path.relative_to(root).as_posix())

    Path(args.out_fixed).write_text("\n".join(fixed) + ("\n" if fixed else ""), encoding="utf-8")
    print(f"Checked {len(targets)} files; fixed {len(fixed)}.")


if __name__ == "__main__":
    main()
