# Malinali

Offline MarianMT playground for African / low-resource languages.
French ↔ Pulaar translator (on-device MarianMT via [`marian_flutter`](https://github.com/malinali-app/marian_flutter)).

## Languages available

On-device **bilateral** MarianMT (Candle). Multilingual `mul` / family models are intentionally out of scope for now (heavier, weaker on phone).

### Already wired (Xenova Opus-MT mirrors)

Afrikaans, Arabic, Chinese, Czech, Danish, Dutch, English, Estonian, Finnish, French, German, Hindi, Hungarian, Indonesian, Italian, Japanese, Korean, Norwegian, Polish, Romanian, Russian, Spanish, Swedish, Thai, Turkish, Ukrainian, Vietnamese, **Xhosa** — plus private **French → Pulaar**.

### African / low-resource bilaterals (Helsinki-NLP OPUS)

Curated in the app catalogue. OPUS [BLEU](https://dl.acm.org/doi/10.3115/1073083.1073135) is shown on the model tile as `BLEU xx.x / 100` when known (quality varies; short greetings can be unreliable).

Candle packs for the full curated set are public under [`malinali-app`](https://huggingface.co/malinali-app) (`config.json` + `model.safetensors` + fast tokenizers), credited to upstream Helsinki-NLP. Example: [`malinali-app/opus-mt-en-ha`](https://huggingface.co/malinali-app/opus-mt-en-ha). Republish / resume:

```bash
python tool/publish_african_candle.py --all          # skip already-complete repos
# python tool/publish_african_candle.py opus-mt-ha-en opus-mt-yo-en
# flutter test test/opus_mt_en_ha_local_test.dart    # local Candle smoke
```

| Language | ISO | Example pairs |
|----------|-----|----------------|
| Hausa | ha | en↔ha, fr↔ha, also de/es/fi/sv |
| Yoruba | yo | yo→en, fr↔yo, also es/fi/sv |
| Igbo | ig | en↔ig, fr↔ig, also de/es/fi/sv |
| Swahili | sw | en→sw, fi→sw |
| Congo Swahili | swc | swc↔en/fr/es/fi/sv |
| Kinyarwanda | rw | en↔rw, fr↔rw, also es/fi/sv |
| Rundi | rn | en↔rn, rn→fr, also de/es/ru |
| Ganda (Luganda) | lg | en↔lg, fr↔lg, also es/fi/sv |
| Shona | sn | en↔sn, fr↔sn, also es/fi/sv |
| Lingala | ln | en↔ln, fr↔ln, also de/es/fi/sv |
| Nyanja / Chewa | ny | en↔ny, fr→ny, also de/es/fi/sv |
| Twi | tw | en→tw, fr→tw, also es/fi/sv |
| Ewe | ee | en↔ee, fr↔ee, also de/es/fi/sv |
| Kabyle | kab | kab→en |
| Tigrinya | ti | en↔ti |
| Tiv | tiv | tiv→en/fr/sv |
| Afrikaans / Xhosa | af, xh | already via Xenova |
| Pulaar (Fula) | ff | fr→ff (private fine-tune) |

Catalogue size: **~110+ bilateral pairs**, **~40 languages** (varies with HF discovery).

## Related repos

- **Runtime engine**: [`marian_flutter`](https://github.com/malinali-app/marian_flutter) — Candle + flutter_rust_bridge
- **Training pipeline**: [`fula-marian-training`](https://github.com/malinali-app/fula-marian-training) — French→Pulaar fine-tune from opus-mt-fr-ha
- **On-device Fula weights**: private [`flutter-painter/french-fula`](https://huggingface.co/flutter-painter/french-fula) (Candle pack, ~285 MB)

## Runtime models

- **Boot default**: public `Xenova/opus-mt-fr-en` (one model per language pair; no duplicate targets).
- **French → Pulaar**: select in translation settings; downloads `flutter-painter/french-fula`.
- **African Helsinki bilaterals**: listed in Traduction settings; OPUS BLEU as `xx.x / 100` (tap opens the BLEU paper).
- **Utiliser mon propre modèle** (*MarianMT only*): Paramètres tile, or Traduction → AppBar **Mon modèle** — paste a HF MarianMT repo id (`org/name`), optional read token for private repos.

```bash
# After rotating the read token in secret.txt:
dart run tool/embed_hf_token.dart
```

Publish / refresh the private Candle pack (needs a **write** token):

```bash
# secret.txt = read token (app). HF_WRITE_TOKEN = write token (publish only).
HF_WRITE_TOKEN=hf_xxx python3 tool/publish_french_fula.py
```
