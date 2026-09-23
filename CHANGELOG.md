# Changelog

## Unreleased

### Training (`training/fr-pul`)

Labeled the merged Turso + ARPRIM + Open-Data bitext. Each split now has a JSONL sidecar (`data/{train,dev,test}.jsonl`) with `origin`, `labels`, and `primary`.

Primary labels: `street`, `glossary`, `scripture`, `literary`, `news`, `ui`, `covid`. Punctuation-only pairs are dropped at ingest.

`train.py` can exclude `scripture,ui,covid`, upsample `street=3`, keep 25% of glossary, and evaluate on street. `demo.py --label street` decodes with `length_penalty=1.2` and a short `max_new_tokens` cap.

Street-mode training is deferred. The current `models/fr-pul` checkpoint stays as-is.

### App rewrite (planned)

The Flutter app will translate with on-device MarianMT only. The Rust Candle bridge is provided; Dart loads `models/fr-pul` and calls it.

Turso, FTS, and lexical search leave the app (not behind a flag). Turso remains a training export source only.

See `training/flutter-marian.md`.
