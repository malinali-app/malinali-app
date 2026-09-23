"""Heuristic labels for French–Pulaar pairs."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

UI_RE = re.compile(
    r"BEGIN_LINK|END_LINK|PREFERENCES_LINK|LANGUAGEEND|START_NUMBER|"
    r"NUMBER_BOLD|[A-Z]{3,}_[A-Z_]{3,}"
)
SCRIPTURE_FR = re.compile(
    r"\b(allah|moïse|moise|abraham|ibl[iî]s|coran|qur[a']?n|évangile|"
    r"evangile|psaume|pharisien|seigneur|jésus|jesus|christ|synagogue|"
    r"apôtre|apotre|verset|torah|bible|ramad[aâ]n|évangile|"
    r"prophète|prophete|pître|epitres?)\b",
    re.I,
)
SCRIPTURE_PUL = re.compile(
    r"\b(alla|muusaa|alqur|yeesu|jawmiraawo|malaa'?ika|ibuliisa|"
    r"iiblis|firawna|injiil)\b",
    re.I,
)
COVID_RE = re.compile(r"covid|convid|corona", re.I)

PRIMARY_ORDER = ("ui", "covid", "scripture", "glossary", "literary", "news", "street")


def classify(french: str, pulaar: str, origin: str, extra: dict[str, str] | None = None) -> list[str]:
    extra = extra or {}
    haystack = f"{french} {pulaar} {extra.get('theme', '')}"
    labels: list[str] = []
    if UI_RE.search(french) or UI_RE.search(pulaar):
        labels.append("ui")
    if COVID_RE.search(haystack):
        labels.append("covid")
    if SCRIPTURE_FR.search(french) or SCRIPTURE_PUL.search(pulaar):
        labels.append("scripture")
    if "dictionary" in origin:
        labels.append("glossary")
    elif origin == "arprim_corpus":
        labels.append("literary")
    elif origin == "open_data_mauritania":
        labels.append("news")
    elif origin.startswith("turso:phrases"):
        labels.append("street")
    if not labels:
        words = len(french.split())
        labels.append("glossary" if words <= 2 else "street")
    return labels


def primary_label(labels: list[str]) -> str:
    for name in PRIMARY_ORDER:
        if name in labels:
            return name
    return "street"


def load_jsonl(path: Path) -> list[dict[str, object]]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def select_rows(
    rows: list[dict[str, object]],
    *,
    exclude: set[str],
    upsample: dict[str, int],
    glossary_keep: float,
    eval_primary: str | None = None,
) -> list[dict[str, object]]:
    selected: list[dict[str, object]] = []
    for row in rows:
        labels = {str(label) for label in (row.get("labels") or [])}
        primary = str(row.get("primary") or "street")
        if labels & exclude:
            continue
        if eval_primary and primary != eval_primary:
            continue
        if primary == "glossary" and glossary_keep < 1:
            source = str(row.get("fr") or "")
            target = str(row.get("pul") or "")
            digest = hashlib.sha256(f"{source}\t{target}".encode()).digest()
            if int.from_bytes(digest[:4], "big") % 100 >= int(glossary_keep * 100):
                continue
        copies = max(1, upsample.get(primary, 1))
        selected.extend([row] * copies)
    return selected
