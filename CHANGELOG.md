# Changelog

## Unreleased

### App rewrite

On-device French → Pulaar via sibling [`marian_flutter`](../marian_flutter) (Candle + flutter_rust_bridge). Startup loads `assets/fr-pul/`; translate shows a single Pulaar hypothesis (street decode defaults).

Removed from the runtime app: Turso sync, `libsql_dart`, FTS/lexical search, SQLite materialization, `secrets.txt`, and `assets/fra-ful/`. Vosk French mic (Android) and Noto Sans remain.

Prepare model assets: `wsl bash scripts/prepare_app_assets.sh` (copies from `training/fr-pul/models/fr-pul/`). See `training/flutter-marian.md`.

Windows desktop: `marian_flutter` exposes `windows` ffiPlugin. Flutter Debug
embeds Cargokit's **dev** Rust profile — Candle needs `[profile.dev] opt-level = 3`
(in `marian_flutter/rust/Cargo.toml`) or translate looks hung. Prefer
`flutter run -d windows --release` for realistic speed. Street decode on-device
uses beams=2 / max 24 (HF demo uses 4/48; Candle beam is costlier without
per-beam KV). Boot warms one translate so the first UI request stays snappy.
Typed-text smoke: `test/translate_page_windows_test.dart` (release DLL + street
decode; asserts the spinner clears; mic Android-only).

### Training (`training/fr-pul`)

Labeled the merged Turso + ARPRIM + Open-Data bitext. Each split now has a JSONL sidecar (`data/{train,dev,test}.jsonl`) with `origin`, `labels`, and `primary`.

Primary labels: `street`, `glossary`, `scripture`, `literary`, `news`, `ui`, `covid`. Punctuation-only pairs are dropped at ingest.

`train.py` excludes `scripture,ui,covid`, upsamples `street=3`, keeps 25% of glossary, and evaluates on street. `demo.py --label street` decodes with `length_penalty=1.2` and a short `max_new_tokens` cap.

Street greetings injected via `inject_greetings.py`: `Bonjour`/`bonjour`/`Bonjour!`/`Hello` → `Mbaɗɗaa`, `Salutations` → `Salminaango` (street, heavily copied). Fast tokenizer export (`marian_flutter/scripts/convert_tokenizer.py`) now marks `<unk>`/`<pad>` special so Candle decode matches HF skip-special.

Greeting finetune (continue from `models/fr-pul`, RTX 4070): HF + Candle both return **Mbaɗɗaa** / **Salminaango** for those prompts.
