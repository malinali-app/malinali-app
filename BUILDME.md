# BUILDME

## Hugging Face read token (private Fula model)

1. Put a **read-only** fine-grained token in `secret.txt` (gitignored), scoped to `flutter-painter/french-fula` repo content read.
2. Obfuscate into the app:

```bash
dart run tool/embed_hf_token.dart
```

This writes `lib/generated/hf_token.g.dart` (XOR obfuscation — not real secret storage).

## Turso credentials (training / legacy)

Create `secrets.txt` at the project root with two lines: database URL, then auth token. The file is gitignored.

## Publish french-fula Candle pack

```bash
HF_WRITE_TOKEN=hf_write_xxx python3 tool/publish_french_fula.py
```

Uploads `config.json`, `model.safetensors`, `tokenizer-enc.json`, `tokenizer-dec.json` from `assets/fr-pul/` (or set `CANDLE_SRC`).

## macOS

flutter build macos
hdiutil create -volname "Malinali" -srcfolder "build/macos/Build/Products/Release/malinali.app" -ov -format UDZO "malinali.dmg"

## Run

flutter run
