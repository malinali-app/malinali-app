"""Pull French–Pulaar pairs from Turso into a stable train/dev/test split.

Reads secrets.txt (line 1 URL, line 2 token). Does not print the token.
"""

from __future__ import annotations

import hashlib
import json
import unicodedata
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "data"
PROBE_CHARS = "ɓɗŋɲƴñƁƊŊƝƳÑ"
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


def clean(text: object) -> str:
    value = unicodedata.normalize("NFC", str(text or "")).strip()
    return " ".join(value.split())


def keep_pair(source: str, target: str) -> bool:
    if not source or not target or source.casefold() == target.casefold():
        return False
    if len(source) > 400 or len(target) > 400:
        return False
    longer = max(len(source), len(target))
    shorter = min(len(source), len(target))
    return longer <= shorter * 8 + 20


def bucket(source: str, target: str) -> int:
    digest = hashlib.sha256(f"{source}\t{target}".encode()).digest()
    return int.from_bytes(digest[:4], "big") % 100


def main() -> None:
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

    pairs: dict[tuple[str, str], str] = {}
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
                source, target = clean(row[0]), clean(row[1])
                if keep_pair(source, target):
                    pairs[(source, target)] = table
            offset += PAGE
            print(f"  read {min(offset, total)}/{total}")

    splits = {"train": [], "dev": [], "test": []}
    char_counts: Counter[str] = Counter()
    sentence_counts = Counter()
    for (source, target), table in sorted(pairs.items()):
        slot = bucket(source, target)
        name = "test" if slot < 5 else "dev" if slot < 10 else "train"
        splits[name].append((source, target))
        for char in PROBE_CHARS:
            char_counts[char] += target.count(char) + source.count(char)
        if len(source.split()) >= 4:
            sentence_counts[name] += 1

    OUT.mkdir(parents=True, exist_ok=True)
    for name, rows in splits.items():
        (OUT / f"{name}.fr").write_text(
            "\n".join(source for source, _ in rows) + ("\n" if rows else ""),
            encoding="utf-8",
        )
        (OUT / f"{name}.pul").write_text(
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
        "special letter counts (both sides):",
    ]
    report.extend(f"  {char}: {char_counts[char]}" for char in PROBE_CHARS)
    text = "\n".join(report) + "\n"
    (OUT / "report.txt").write_text(text, encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
