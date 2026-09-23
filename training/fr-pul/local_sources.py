"""Load ARPRIM dictionary, ARPRIM sentences, and Open-Data Mauritania bitext."""

from __future__ import annotations

from collections import Counter
from pathlib import Path

from bitext import add_pair, clean, find_snapshot, load_json, looks_pulaar

COVID_MARKERS = ("covid", "covid-19", "convid")


def split_pulaar_variants(*chunks: object) -> list[str]:
    seen: set[str] = set()
    variants: list[str] = []
    for chunk in chunks:
        for part in clean(chunk).split(" / "):
            value = part.strip(" /")
            if value and value.casefold() not in seen:
                seen.add(value.casefold())
                variants.append(value)
    return variants


def is_covid(*parts: object) -> bool:
    haystack = " ".join(str(part or "") for part in parts).casefold()
    return any(marker in haystack for marker in COVID_MARKERS)


def ingest_arprim_dictionary(
    training_root: Path,
    pairs: dict[tuple[str, str], str],
    stats: Counter[str],
) -> None:
    path = find_snapshot(
        training_root,
        "ARPRIM--Pulaar_Dictionary",
        "ARPRIM_terminologies_v18.json",
    )
    rows = load_json(path)
    if not isinstance(rows, list):
        raise SystemExit(f"Unexpected dictionary format in {path}")
    origin = "arprim_dictionary"
    for row in rows:
        if not isinstance(row, dict):
            stats[f"{origin}:dropped"] += 1
            continue
        french = clean(row.get("francais"))
        if looks_pulaar(french):
            stats[f"{origin}:dropped"] += 1
            continue
        variants = split_pulaar_variants(row.get("pulaar"), row.get("pulaar_alt"))
        if not variants:
            stats[f"{origin}:dropped"] += 1
            continue
        for pulaar in variants:
            add_pair(pairs, french, pulaar, origin, stats)


def ingest_arprim_corpus(
    training_root: Path,
    pairs: dict[tuple[str, str], str],
    stats: Counter[str],
) -> None:
    path = find_snapshot(
        training_root,
        "ARPRIM--pulaar_fulfulde",
        "ARPRIM_corpus_phrases_v1.jsonl",
    )
    rows = load_json(path)
    origin = "arprim_corpus"
    for row in rows:
        if not isinstance(row, dict):
            stats[f"{origin}:dropped"] += 1
            continue
        if is_covid(row.get("t"), row.get("s"), row.get("f")):
            stats[f"{origin}:covid"] += 1
            continue
        add_pair(pairs, row.get("f"), row.get("p"), origin, stats)


def ingest_open_data(
    training_root: Path,
    pairs: dict[tuple[str, str], str],
    stats: Counter[str],
) -> None:
    path = training_root / "pulaar_french_parallel_corpus.json"
    if not path.is_file():
        raise SystemExit(f"Missing {path}")
    rows = load_json(path)
    if not isinstance(rows, list):
        raise SystemExit(f"Unexpected Open-Data format in {path}")
    origin = "open_data_mauritania"
    for row in rows:
        if not isinstance(row, dict):
            stats[f"{origin}:dropped"] += 1
            continue
        add_pair(
            pairs,
            row.get("Translated"),
            row.get("Original"),
            origin,
            stats,
            require_pulaar=True,
        )


def ingest_local_sources(
    training_root: Path,
    pairs: dict[tuple[str, str], str],
    stats: Counter[str],
) -> None:
    ingest_arprim_dictionary(training_root, pairs, stats)
    ingest_arprim_corpus(training_root, pairs, stats)
    ingest_open_data(training_root, pairs, stats)
