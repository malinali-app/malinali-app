# Malinali

Offline MarianMT playground for African / low-resource languages.
French ↔ Pulaar translator (on-device MarianMT via [`marian_flutter`](https://github.com/malinali-app/marian_flutter)).

## Related repos

- **Runtime engine**: [`marian_flutter`](https://github.com/malinali-app/marian_flutter) — Candle + flutter_rust_bridge
- **Training pipeline**: [`fula-marian-training`](https://github.com/malinali-app/fula-marian-training) — French→Pulaar fine-tune from opus-mt-fr-ha
- **On-device Fula weights**: private [`flutter-painter/french-fula`](https://huggingface.co/flutter-painter/french-fula) (Candle pack, ~285 MB)

## Runtime models

- **Boot default**: public `Xenova/opus-mt-fr-en` (one model per language pair; no duplicate targets).
- **French → Pulaar**: select in translation settings; downloads `flutter-painter/french-fula`.
- **Bring Your Own**: Paramètres → Traduction → *Avancé — Bring Your Own* — paste a HF Marian/Candle repo id (`org/name`), optional read token for private repos.

```bash
# After rotating the read token in secret.txt:
dart run tool/embed_hf_token.dart
```

Publish / refresh the private Candle pack (needs a **write** token):

```bash
# secret.txt = read token (app). HF_WRITE_TOKEN = write token (publish only).
HF_WRITE_TOKEN=hf_xxx python3 tool/publish_french_fula.py
```

## TODOs

- Speech-to-text Fula: https://huggingface.co/cawoylel/fula-whisper-medium
