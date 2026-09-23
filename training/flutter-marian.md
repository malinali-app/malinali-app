# MarianMT Flutter rewrite

The rewrite makes **on-device MarianMT the translator**. Turso, FTS, and lexical search leave the app. The Rust Candle bridge is provided; Dart only loads the model and calls it.

## What stays

- French speech in via Vosk (Android).
- Noto Sans for ɓ ɗ ŋ ɲ ƴ.
- One screen: source box, mic, translate, Pulaar output.
- Offline-first. The model ships in the APK / app files. Nothing is fetched from Turso.

## What goes (delete, do not flag)

- `TursoSyncService`, replica download, `libsql_dart`, `secrets.txt` as an app asset.
- `SearchService`, FTS, lexical token lookup, result lists (`lib/malinali_app.dart` `_translate`).
- SQLite phrase/dictionary materialization (`database_materializer`, `search_index_service`, `replica_storage`, `sync_database_access`, `database_bootstrap`).
- The ~1,700-line `malinali_app.dart` god widget. Split into `TranslatePage`, `MarianService`, `SpeechService`.

Turso remains a **training** source only (`training/fr-pul/export_turso.py`). It is not a runtime dependency.

## Runtime

Load the HF Marian folder already produced by training (`models/fr-pul/`):

- `config.json`
- `model.safetensors` (~285 MB)
- SentencePiece + `vocab.json`

Call the **provided Rust Candle Marian bridge** from Dart. Do not add a second FFI, JNI, or PyTorch path. Bergamot/intgemm is a later pack if this checkpoint is worth it.

Init once at startup (replaces today’s DB seed). Translate off the UI isolate so the frame does not jank.

## Decode contract (must match `demo.py`)

French → Pulaar only in v1. Pass these through the bridge:

- `num_beams=4`
- `length_penalty=1.2`
- `no_repeat_ngram_size=3`
- `max_new_tokens = min(48, 8 + 2 * source_word_count)`

Show **one** hypothesis. No n-best list until quality is there.

Street-mode retraining is **not** a rewrite blocker. Ship the current `models/fr-pul` checkpoint until a later train.

## UI

- Input: French text or Vosk.
- Output: a single Pulaar string, copy/share.
- No dictionary hits, no “also in the lexicon” footer.
- Direction switcher stays disabled until a `pul-fr` checkpoint exists (`opus-mt-ha-fr` fine-tune, same pipeline).

## Assets and size

285 MB safetensors is large for Play. Options, in order:

1. Ship the model as an on-demand Android asset pack / first-run download to app files.
2. Quantize later (int8 / intgemm) once chrF on the street slice is acceptable.

Do not ship Turso replicas, `phrases.tsv`, or `assets/fra-ful/` in the Marian release.

## Work slices

1. **Strip Turso/FTS from Dart.** New `TranslatePage`. Drop `libsql_dart` and the sync/search services listed above.
2. **Wire `MarianService` to the provided Rust bridge.** Load `models/fr-pul`, apply the decode contract, golden-test a dozen street sentences against `demo.py --label street` (WSL).
3. **Startup:** unpack/load the model, progress screen (replaces DB seed status).
4. **Pulaar → French** as a second model file, same UI switcher, same bridge.
