"""Pull French–Pulaar pairs from Turso and merge local ARPRIM / Open-Data sources.

Reads secrets.txt (line 1 URL, line 2 token). Does not print the token.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from bitext import add_pair, write_splits
from local_sources import ingest_local_sources

ROOT = HERE.parents[1]
OUT = HERE / "data"
TRAINING = HERE.parent
SOURCE_KEYS = (
    "source_word",
    "french",
    "fr",
    "texte_source",
    "text_fr",
    "src",
)
TARGET_KEYS = (
    "translated_word",
    "pulaar",
    "fulfulde",
    "ff",
    "texte_traduit",
    "text_ff",
    "tgt",
    "target",
)
PAGE = 1000


def load_secrets() -> tuple[str, str]:
    path = ROOT / "secrets.txt"
    lines = [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    if len(lines) < 2:
        raise SystemExit(f"{path} needs a URL on line 1 and a token on line 2")
    url = lines[0]
    if url.startswith("libsql://"):
        url = "https://" + url[len("libsql://") :]
    elif url.startswith("http://"):
        url = "https://" + url[len("http://") :]
    elif not url.startswith("https://"):
        url = "https://" + url
    return url.rstrip("/"), lines[1]


def pipeline(base: str, token: str, sql: str) -> list[list[object]]:
    body = json.dumps(
        {
            "requests": [
                {"type": "execute", "stmt": {"sql": sql}},
                {"type": "close"},
            ]
        }
    ).encode()
    request = urllib.request.Request(
        base + "/v2/pipeline",
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[:500]
        raise SystemExit(f"Turso HTTP {error.code}: {detail}") from error

    results = payload.get("results") or []
    if not results:
        raise SystemExit(f"Empty Turso response for: {sql[:80]}")
    first = results[0]
    if first.get("type") == "error":
        raise SystemExit(f"Turso error: {first.get('error')}")
    result = first["response"]["result"]
    rows = []
    for row in result.get("rows") or []:
        rows.append([unwrap(cell) for cell in row])
    return rows


def unwrap(cell: object) -> object:
    if isinstance(cell, dict) and "value" in cell:
        return cell["value"]
    return cell


def quote_ident(name: str) -> str:
    if not name.replace("_", "").isalnum():
        raise SystemExit(f"Unexpected SQL name: {name}")
    return '"' + name + '"'


def pick_column(columns: list[str], keys: tuple[str, ...], role: str) -> str | None:
    lowered = {column.lower(): column for column in columns}
    for key in keys:
        if key in lowered:
            return lowered[key]
    if "source_word" in lowered:
        return None
    for column in columns:
        low = column.lower()
        if low == role or low.endswith("_" + role):
            return column
    return None


def ingest_turso(
    pairs: dict[tuple[str, str], dict[str, str]],
    stats: Counter[str],
) -> None:
    base, token = load_secrets()
    host = base.removeprefix("https://")
    print(f"Turso host: {host}")

    tables = [
        row[0]
        for row in pipeline(
            base,
            token,
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        )
        if row and isinstance(row[0], str)
    ]
    print("Tables:", ", ".join(tables) or "(none)")

    for table in tables:
        if table in {"documents", "search_index_meta", "data_sources"}:
            continue
        info = pipeline(base, token, f"PRAGMA table_info({quote_ident(table)})")
        columns = [str(row[1]) for row in info if len(row) > 1]
        source_column = pick_column(columns, SOURCE_KEYS, "source")
        target_column = pick_column(columns, TARGET_KEYS, "translation")
        if not source_column or not target_column or source_column == target_column:
            print(f"Skip {table}: {columns}")
            continue
        total = int(
            pipeline(base, token, f"SELECT COUNT(*) FROM {quote_ident(table)}")[0][0]
        )
        print(f"{table}: {total} rows ({source_column} -> {target_column})")
        offset = 0
        while offset < total:
            page = pipeline(
                base,
                token,
                "SELECT "
                f"{quote_ident(source_column)}, {quote_ident(target_column)} "
                f"FROM {quote_ident(table)} LIMIT {PAGE} OFFSET {offset}",
            )
            if not page:
                break
            for row in page:
                add_pair(pairs, row[0], row[1], f"turso:{table}", stats)
            offset += PAGE
            print(f"  read {min(offset, total)}/{total}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--local-only",
        action="store_true",
        help="Skip Turso and rebuild the split from local sources only.",
    )
    args = parser.parse_args()

    pairs: dict[tuple[str, str], dict[str, str]] = {}
    stats: Counter[str] = Counter()
    if not args.local_only:
        ingest_turso(pairs, stats)
    print("Merging local ARPRIM and Open-Data sources")
    ingest_local_sources(TRAINING, pairs, stats)
    text = write_splits(pairs, OUT, stats)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print(text)


if __name__ == "__main__":
    main()
