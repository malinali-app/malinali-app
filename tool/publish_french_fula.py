"""Create private flutter-painter/french-fula and upload the Candle pack.

Uses HF_WRITE_TOKEN (or secret_write.txt) for upload — the app's secret.txt is
read-only and cannot publish.
"""

from __future__ import annotations

import os
from pathlib import Path

from huggingface_hub import HfApi, create_repo

ROOT = Path(__file__).resolve().parents[1]


def write_token() -> str:
    env = os.environ.get("HF_WRITE_TOKEN", "").strip()
    if env:
        return env
    path = ROOT / "secret_write.txt"
    if path.is_file():
        return path.read_text(encoding="utf-8").strip()
    raise SystemExit(
        "Need a write-capable HF token: set HF_WRITE_TOKEN or create secret_write.txt.\n"
        "(secret.txt is read-only for the app and cannot upload.)"
    )


TOKEN = write_token()
SRC = Path(os.environ.get("CANDLE_SRC", str(ROOT / "assets" / "fr-pul")))
REPO_ID = "flutter-painter/french-fula"
FILES = (
    "config.json",
    "model.safetensors",
    "tokenizer-enc.json",
    "tokenizer-dec.json",
)

README = """---
language:
- fr
- ff
tags:
- translation
- marian
- candle
- french
- fula
- pulaar
library_name: transformers
pipeline_tag: translation
---

# French → Pulaar (Fula) Marian / Candle

Private on-device pack for Malinali. Fine-tuned MarianMT weights in safetensors form for Candle (`marian_flutter`).

## Files (required)

| File | Role |
|------|------|
| `config.json` | Marian config |
| `model.safetensors` | Weights |
| `tokenizer-enc.json` | French (source) fast tokenizer |
| `tokenizer-dec.json` | Pulaar (target) fast tokenizer |

Direction: **French → Pulaar**.
"""


def main() -> None:
    for name in FILES:
        path = SRC / name
        if not path.is_file():
            raise SystemExit(f"Missing {path}")

    create_repo(REPO_ID, token=TOKEN, private=True, repo_type="model", exist_ok=True)
    api = HfApi(token=TOKEN)

    readme = SRC / "_README_upload.md"
    readme.write_text(README, encoding="utf-8")
    try:
        api.upload_file(
            path_or_fileobj=str(readme),
            path_in_repo="README.md",
            repo_id=REPO_ID,
            repo_type="model",
        )
    finally:
        readme.unlink(missing_ok=True)

    for name in FILES:
        print(f"Uploading {name}…")
        api.upload_file(
            path_or_fileobj=str(SRC / name),
            path_in_repo=name,
            repo_id=REPO_ID,
            repo_type="model",
        )
        print(f"  done {name}")

    info = api.list_repo_files(REPO_ID, repo_type="model")
    print("Repo files:", info)
    print(f"Published https://huggingface.co/{REPO_ID}")


if __name__ == "__main__":
    main()
