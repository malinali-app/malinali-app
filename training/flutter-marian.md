# MarianMT Flutter rewrite

The rewrite makes **on-device MarianMT the translator** via sibling package [`marian_flutter`](../../marian_flutter/README.md) (Candle + `flutter_rust_bridge`). Turso, FTS, and lexical search leave the app. Do not use ONNX or `onnx_translation`.

## What stays

- French speech in via Vosk (Android).
- Noto Sans for ɓ ɗ ŋ ɲ ƴ.
- One screen: source box, mic, translate, Pulaar output.
- Offline-first. The Marian folder ships as Flutter assets (or a first-run pack). Nothing is fetched from Turso.

## What goes (delete, do not flag)

- `TursoSyncService`, replica download, `libsql_dart`, `secrets.txt` as an app asset.
- `SearchService`, FTS, lexical token lookup, result lists (`lib/malinali_app.dart` `_translate`).
- SQLite phrase/dictionary materialization (`database_materializer`, `search_index_service`, `replica_storage`, `sync_database_access`, `database_bootstrap`).
- The ~1,700-line `malinali_app.dart` god widget. Split into `TranslatePage` and `SpeechService`. Translation is `MarianService` from `marian_flutter`.

Turso remains a **training** source only (`training/fr-pul/export_turso.py`). It is not a runtime dependency.

## Runtime

Path-depend on the sibling package (Android first, `arm64-v8a` / `armeabi-v7a` via Cargokit):

```yaml
dependencies:
  marian_flutter:
    path: ../marian_flutter
```

```dart
await MarianService.initRust();
final marian = await MarianService.loadFromAssets(
  assetFolder: 'assets/fr-pul',
);
final pulaar = await marian.translate(french);
```

Ship `assets/fr-pul/` with:

| File | Role |
|------|------|
| `config.json` | Marian config (Candle) |
| `model.safetensors` | Weights from `models/fr-pul/` |
| `tokenizer-enc.json` | Source (French) fast tokenizer |
| `tokenizer-dec.json` | Target (Pulaar) fast tokenizer |

Convert Helsinki SPM files after train (from the malinali-app repo root):

```bash
python ../marian_flutter/scripts/convert_tokenizer.py training/fr-pul/models/fr-pul
```

Then copy `config.json`, `model.safetensors`, `tokenizer-enc.json`, and `tokenizer-dec.json` into `assets/fr-pul/`.

Init Rust once at process start (replaces today’s DB seed). `translate` is async.

## Decode contract

`marian_flutter` defaults already match `demo.py`:

- `numBeams: 4`
- `maxNewTokens: 48`
- `lengthPenalty: 1.2`
- `noRepeatNgramSize: 3`

Show **one** hypothesis. No n-best list until quality is there.

## UI

- Input: French text or Vosk.
- Output: a single Pulaar string, copy/share.
- No dictionary hits, no “also in the lexicon” footer.
- Direction switcher stays disabled until a `pul-fr` folder exists (`opus-mt-ha-fr` fine-tune, same tokenizer convert).

## Assets and size

`model.safetensors` is ~285 MB, large for Play. Options, in order:

1. Ship `assets/fr-pul/` as an on-demand Android asset pack / first-run download.
2. Quantize later once street chrF is acceptable.

Do not ship Turso replicas, `phrases.tsv`, `assets/fra-ful/`, ONNX graphs, or SPM files the app does not load.

## Work slices

1. **Street-mode train** — done (`demo.py --label street`, chrF 22.41).
2. **Tokenizer convert** — done; use `scripts/prepare_app_assets.sh` to refresh `assets/fr-pul/`.
3. **Strip Turso/FTS + wire `marian_flutter`** — done (`TranslatePage`, Marian boot screen).
4. Golden-test a dozen street sentences against `demo.py --label street` (follow-up).
5. **Pulaar → French** as a second asset folder, same UI switcher, same package.
