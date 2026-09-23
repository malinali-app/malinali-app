"""Shared French–Pulaar pair cleanup, filters, and split writing."""

from __future__ import annotations

import hashlib
import json
import unicodedata
from collections import Counter
from pathlib import Path

PROBE_CHARS = "ɓɗŋɲƴñƁƊŊƝƳÑ"
APOSTROPHES = str.maketrans({"’": "'", "ʼ": "'", "´": "'", "`": "'"})
MAX_CHARS = 1200


def clean(text: object) -> str:
    value = unicodedata.normalize("NFC", str(text or "")).strip()
    value = value.translate(APOSTROPHES)
    return " ".join(value.split())


def keep_pair(source: str, target: str) -> bool:
    if not source or not target or source.casefold() == target.casefold():
        return False
    if len(source) > MAX_CHARS or len(target) > MAX_CHARS:
        return False
    longer = max(len(source), len(target))
    shorter = min(len(source), len(target))
    return longer <= shorter * 8 + 20


def looks_pulaar(text: str) -> bool:
    return any(char in text for char in PROBE_CHARS)


def bucket(source: str, target: str) -> int:
    digest = hashlib.sha256(f"{source}\t{target}".encode()).digest()
    return int.from_bytes(digest[:4], "big") % 100


def add_pair(
    pairs: dict[tuple[str, str], str],
    source: object,
    target: object,
    origin: str,
    stats: Counter[str],
    *,
    require_pulaar: bool = False,
) -> None:
    french, pulaar = clean(source), clean(target)
    if require_pulaar and not looks_pulaar(pulaar):
        stats[f"{origin}:dropped"] += 1
        return
    if not keep_pair(french, pulaar):
        stats[f"{origin}:dropped"] += 1
        return
    key = (french, pulaar)
    if key in pairs:
        stats[f"{origin}:overlap"] += 1
        return
    pairs[key] = origin
    stats[f"{origin}:kept"] += 1


def load_json(path: Path) -> object:
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".jsonl":
        return [json.loads(line) for line in text.splitlines() if line.strip()]
    return json.loads(text)


def find_snapshot(training_root: Path, repo: str, filename: str) -> Path:
    matches = sorted(training_root.glob(f"datasets--{repo}/snapshots/*/{filename}"))
    if not matches:
        raise SystemExit(f"Missing {filename} under datasets--{repo}")
    return matches[-1]


def write_splits(
    pairs: dict[tuple[str, str], str],
    out: Path,
    stats: Counter[str],
) -> str:
    splits: dict[str, list[tuple[str, str]]] = {"train": [], "dev": [], "test": []}
    char_counts: Counter[str] = Counter()
    sentence_counts: Counter[str] = Counter()
    origin_counts: Counter[str] = Counter()
    for (source, target), origin in sorted(pairs.items()):
        slot = bucket(source, target)
        name = "test" if slot < 5 else "dev" if slot < 10 else "train"
        splits[name].append((source, target))
        origin_counts[origin] += 1
        for char in PROBE_CHARS:
            char_counts[char] += target.count(char) + source.count(char)
        if len(source.split()) >= 4:
            sentence_counts[name] += 1

    out.mkdir(parents=True, exist_ok=True)
    for name, rows in splits.items():
        (out / f"{name}.fr").write_text(
            "\n".join(source for source, _ in rows) + ("\n" if rows else ""),
            encoding="utf-8",
        )
        (out / f"{name}.pul").write_text(
            "\n".join(target for _, target in rows) + ("\n" if rows else ""),
            encoding="utf-8",
        )

    report = [
        f"unique pairs: {len(pairs)}",
        f"train: {len(splits['train'])}",
        f"dev: {len(splits['dev'])}",
        f"test: {len(splits['test'])}",
        "full sentences (source has 4+ words): "
        + ", ".join(f"{name}={sentence_counts[name]}" for name in splits),
        "pairs by origin:",
    ]
    report.extend(f"  {origin}: {origin_counts[origin]}" for origin in sorted(origin_counts))
    report.append("ingest stats:")
    report.extend(f"  {key}: {stats[key]}" for key in sorted(stats))
    report.append("special letter counts (both sides):")
    report.extend(f"  {char}: {char_counts[char]}" for char in PROBE_CHARS)
    text = "\n".join(report) + "\n"
    (out / "report.txt").write_text(text, encoding="utf-8")
    return text
