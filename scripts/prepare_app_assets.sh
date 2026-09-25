#!/usr/bin/env bash
# Copy Candle Marian files from the training checkpoint into app assets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# When run via WSL against Windows paths:
if [[ "$ROOT" != /mnt/c/* ]] && [[ -d /mnt/c/Users/PierreGancel/Documents/git_malinali/malinali-app ]]; then
  ROOT=/mnt/c/Users/PierreGancel/Documents/git_malinali/malinali-app
fi

SRC="$ROOT/training/fr-pul/models/fr-pul"
DEST="$ROOT/assets/fr-pul"

if [[ ! -d "$SRC" ]]; then
  echo "Missing model folder: $SRC" >&2
  exit 1
fi

mkdir -p "$DEST"
for name in config.json model.safetensors tokenizer-enc.json tokenizer-dec.json; do
  if [[ ! -f "$SRC/$name" ]]; then
    echo "Missing $SRC/$name — run marian_flutter tokenizer convert first." >&2
    exit 1
  fi
  cp -f "$SRC/$name" "$DEST/$name"
  echo "copied $name"
done

# Optional generation config (not required by marian_flutter)
if [[ -f "$SRC/generation_config.json" ]]; then
  cp -f "$SRC/generation_config.json" "$DEST/generation_config.json"
fi

ls -lh "$DEST"
echo "DONE — assets ready at $DEST"
