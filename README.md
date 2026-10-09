# Malinali

Offline voice and text translation for African / low-resource languages
(on-device Whisper + MarianMT via [`marian_flutter`](https://github.com/malinali-app/marian_flutter)).

## Voice home

The app opens on a WhatsApp-style **conversation** screen.

1. First launch: pick spoken language (Wolof / Swahili / Yoruba), target language (English→X Marian, French pinned), and speech model size (**250 Mo** recommended, or 75 Mo).
2. Hold the mic to record (slide left to cancel, slide up to lock). Cap 30 seconds.
3. Speech reaches English by the best chain available for that language, then Marian translates English→target. Android TTS plays the result on tap.

Speech chain (first match wins, same ISO on both sides of a hop):

1. Whisper fine-tune that emits English (none shipped yet; catalogue slot `emitsEnglish`).
2. Whisper fine-tune that transcribes the source language **and** a Marian source→English pack (live today: Yoruba → `opus-mt-yo-en`; Wolof → [`malinali-app/traduction-wolof-en`](https://huggingface.co/malinali-app/traduction-wolof-en)).
3. Generic multilingual Whisper (chosen size) with translate-to-English (Swahili lands here).

Advanced modes live under Paramètres (no bottom bar):

- **Traduction écrite** — typed MarianMT only (no mic).
- **Transcription audio** — Vosk only (file, share target, or plain live mic).
- **Utiliser mon propre modèle** — BYO MarianMT for written translation.

[`LocaleNLP/eng_wolof`](https://huggingface.co/LocaleNLP/eng_wolof) (English→Wolof) is wired as [`malinali-app/traduction-en-wolof`](https://huggingface.co/malinali-app/traduction-en-wolof): SentencePiece converted to a Candle pack. Base is multilingual `opus-mt-en-mul` used as a dedicated en→wo fine-tune; the app prefixes `>>wol<< ` (ISO 639-3 token) on every source string.

## Languages available (written Marian)

On-device **bilateral** MarianMT (Candle). Multilingual `mul` / family models are intentionally out of scope for now (heavier, weaker on phone).

### Already wired (Xenova Opus-MT mirrors)

Afrikaans, Arabic, Chinese, Czech, Danish, Dutch, English, Estonian, Finnish, French, German, Hindi, Hungarian, Indonesian, Italian, Japanese, Korean, Norwegian, Polish, Romanian, Russian, Spanish, Swedish, Thai, Turkish, Ukrainian, Vietnamese, **Xhosa** — plus private **French → Pulaar**, **French → Wolof**, and **English → Wolof**.

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
| Wolof | wo | wo→en ([`malinali-app/traduction-wolof-en`](https://huggingface.co/malinali-app/traduction-wolof-en) from [`LocaleNLP/localenlp-wol-eng-0.03`](https://huggingface.co/LocaleNLP/localenlp-wol-eng-0.03), fine-tune of opus-mt-mul-en; BLEU 68.5); fr→wo ([`malinali-app/traduction-fr-wolof`](https://huggingface.co/malinali-app/traduction-fr-wolof), fine-tune of opus-mt-fr-en; BLEU 9.3); en→wo ([`malinali-app/traduction-en-wolof`](https://huggingface.co/malinali-app/traduction-en-wolof) from [`LocaleNLP/eng_wolof`](https://huggingface.co/LocaleNLP/eng_wolof), fine-tune of opus-mt-en-mul; BLEU 76.1 self-reported) |

Catalogue size: **~110+ bilateral pairs**, **~40 languages** (varies with HF discovery).

## Related repos

- **Runtime engine**: [`marian_flutter`](https://github.com/malinali-app/marian_flutter) — Candle + flutter_rust_bridge
- **Training pipeline**: [`fula-marian-training`](https://github.com/malinali-app/fula-marian-training) — French→Pulaar fine-tune from opus-mt-fr-ha
- **On-device Fula weights**: private [`flutter-painter/french-fula`](https://huggingface.co/flutter-painter/french-fula) (Candle pack, ~285 MB)

## Runtime models

- **Voice boot**: no Marian download until the voice pair or Traduction écrite needs one. Voice defaults Wolof→French: Whisper [`M9and2M/whisper-small-wolof`](https://huggingface.co/M9and2M/whisper-small-wolof) as [`malinali-app/whisper-small-wolof-ggml`](https://huggingface.co/malinali-app/whisper-small-wolof-ggml) (q8, ~252 Mo, prompted with English — Whisper has no `<|wo|>` token), then `malinali-app/traduction-wolof-en`, then `Xenova/opus-mt-en-fr`.
- **Written last model**: restored from `last_selected_model.json` when opening Traduction écrite; otherwise tiny Helsinki FR→EN.
- **French → Pulaar**: select in translation settings; downloads `flutter-painter/french-fula`.
- **French → Wolof**: select in translation settings; downloads `malinali-app/traduction-fr-wolof` (Candle pack of [`makhtar7186/traduction_fr_wolof`](https://huggingface.co/makhtar7186/traduction_fr_wolof)). Tokenizer is the unchanged opus-mt-fr-en SentencePiece pair, converted to `tokenizer-enc.json` / `tokenizer-dec.json`. Republish with `python tools/publish_model_hf/publish_fr_wolof.py` (root `model.safetensors` only, not the training checkpoints).
- **English → Wolof**: select in translation settings or as a voice target; downloads `malinali-app/traduction-en-wolof` (Candle pack of [`LocaleNLP/eng_wolof`](https://huggingface.co/LocaleNLP/eng_wolof)). Same convert path as the African Helsinki packs, plus a required `>>wol<< ` source prefix (`sourcePrefix` on the catalogue card). Republish with `python tools/publish_model_hf/publish_eng_wolof.py` (`--convert-only` to skip weights / upload).
- **Wolof → English**: voice source Wolof downloads `malinali-app/traduction-wolof-en` (Candle pack of [`LocaleNLP/localenlp-wol-eng-0.03`](https://huggingface.co/LocaleNLP/localenlp-wol-eng-0.03), fine-tune of opus-mt-mul-en; BLEU 68.5). No source prefix (`>>wol<<` is not in the vocab). Whisper `wolof-small` transcribes, then this pack translates to English. Republish with `python tools/publish_model_hf/publish_wol_eng.py`.
- **African Helsinki bilaterals**: listed in Traduction écrite settings; OPUS BLEU as `xx.x / 100` (tap opens the BLEU paper).
- **Utiliser mon propre modèle** (*MarianMT only*): Paramètres tile — paste a HF MarianMT repo id (`org/name`), optional read token for private repos.

```bash
# After rotating the read token in secret.txt:
dart run tool/embed_hf_token.dart
```

Publish / refresh the private Candle pack (needs a **write** token):

```bash
# secret.txt = read token (app). HF_WRITE_TOKEN = write token (publish only).
HF_WRITE_TOKEN=hf_xxx python3 tool/publish_french_fula.py
```
