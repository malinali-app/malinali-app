# Malinali

Offline voice and text translation for African / low-resource languages
(on-device Whisper via [`sherpa_onnx`](https://pub.dev/packages/sherpa_onnx) + MarianMT via ONNX on Android/Windows; Candle [`marian_flutter`](https://github.com/malinali-app/marian_flutter) only for written catalog packs).

## Voice home

The Wolof to french/english translation is terrible (same for source low resource language)
The MarianMT model is actually decent, but the wording is so bad, so different that it goes astray.
Only use English or French as source.


The app opens on a WhatsApp-style **conversation** screen.

1. **First launch**: pick source language (**English**, **Français**, or **Wolof**), pick target language, and download the on-device model (with network check and wakelock during download).
2. Hold the mic to record (slide left to cancel, slide up to lock). Cap 30 seconds.
3. Speech is transcribed by Whisper, the Whisper model is released from RAM, and MarianMT translates to the target language. Android TTS plays the result on tap.

### Voice translation pipeline & models

All inference runs 100% on-device (Whisper STT unloads before MarianMT loads to prevent RAM exhaustion on phones).

#### 1. Spoken languages (STT, sherpa-onnx int8)
- **Wolof (`wo`)**: [`malinali-app/whisper-small-wolof-onnx`](https://huggingface.co/malinali-app/whisper-small-wolof-onnx) (from `M9and2M/whisper-small-wolof`, prompted with `en` — Whisper has no `<|wo|>` token).
- **Yoruba (`yo`)**: [`malinali-app/whisper-small-yoruba-onnx`](https://huggingface.co/malinali-app/whisper-small-yoruba-onnx) (from `LyngualLabs/whisper-small-yoruba`).
- **French / English**: [`malinali-app/whisper-small-onnx`](https://huggingface.co/malinali-app/whisper-small-onnx) (~375 Mo) or [`whisper-tiny-onnx`](https://huggingface.co/malinali-app/whisper-tiny-onnx) (~103 Mo).

#### 2. Translation paths (MarianMT)
| Source | Target | Model / Strategy | BLEU / Quality |
|--------|--------|------------------|----------------|
| **Wolof (`wo`)** | **English (`en`)** | `malinali-app/traduction-wolof-en` (LocaleNLP fine-tune) | **BLEU 68.5** |
| **Wolof (`wo`)** | **French (`fr`)** | **Cascade**: `wo → en` (`traduction-wolof-en`) then `en → fr` (`Xenova/opus-mt-en-fr`) | **BLEU ~28–35** (no direct `wo→fr` Marian model exists) |
| **French (`fr`)** | **English (`en`)** | Voice: [`malinali-app/opus-mt-fr-en-onnx`](https://huggingface.co/malinali-app/opus-mt-fr-en-onnx) (standard Helsinki `opus-mt-fr-en`). Written boot may still use the tiny pack. | BLEU ~40+ |
| **French (`fr`)** | **Wolof (`wo`)** | **Cascade**: `fr → en` ([`malinali-app/opus-mt-fr-en-onnx`](https://huggingface.co/malinali-app/opus-mt-fr-en-onnx)) then `en → wo` (`traduction-en-wolof` / [`LocaleNLP/eng_wolof`](https://huggingface.co/LocaleNLP/eng_wolof), prefix `>>wol<< `) | EN→WO **BLEU 76.1** (direct `traduction-fr-wolof` is BLEU 9.3, not used for voice/auto) |
| **French (`fr`)** | **African languages** | Helsinki bilaterals with **BLEU ≥ 30** (e.g. Lingála `opus-mt-fr-ln` BLEU 30.5) | BLEU ≥ 30 |
| **English (`en`)** | **French (`fr`)** | `Xenova/opus-mt-en-fr` | BLEU ~43.0 |
| **English (`en`)** | **Wolof (`wo`)** | `malinali-app/traduction-en-wolof` (prefix `>>wol<< `) | **BLEU 76.1** |
| **English (`en`)** | **African languages** | Helsinki bilaterals with **BLEU ≥ 30** (Igbo 39.5, Twi 38.2, Ewe 38.2, Shona 38.0, Lingála 36.7, Hausa 34.1, Kinyarwanda 33.3, Nyanja 31.4, Ganda 30.4) | BLEU ≥ 30 |

#### Testing / benchmarking Wolof → French BLEU score
Because Helsinki-NLP never released an `opus-mt-wo-fr` pair, the app bridges Wolof through English to French.
To compute sacreBLEU on test sets (e.g. FLEURS `google/fleurs` split `wo_sn`):

```python
import sacrebleu, torch
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM

# 1. wo -> en
tok_wo = AutoTokenizer.from_pretrained("malinali-app/traduction-wolof-en")
mt_wo = AutoModelForSeq2SeqLM.from_pretrained("malinali-app/traduction-wolof-en")
# 2. en -> fr
tok_fr = AutoTokenizer.from_pretrained("Helsinki-NLP/opus-mt-en-fr")
mt_fr = AutoModelForSeq2SeqLM.from_pretrained("Helsinki-NLP/opus-mt-en-fr")

def wo_to_fr(sentences: list[str]) -> list[str]:
    en = tok_wo.batch_decode(mt_wo.generate(**tok_wo(sentences, return_tensors="pt", padding=True)), skip_special_tokens=True)
    return tok_fr.batch_decode(mt_fr.generate(**tok_fr(en, return_tensors="pt", padding=True)), skip_special_tokens=True)

# bleuscore = sacrebleu.corpus_bleu(wo_to_fr(wolof_test_sentences), [french_references])
```

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

- **Voice boot**: no Marian download until the voice pair or Traduction écrite needs one. Voice defaults Wolof→French: Whisper [`M9and2M/whisper-small-wolof`](https://huggingface.co/M9and2M/whisper-small-wolof) as [`malinali-app/whisper-small-wolof-onnx`](https://huggingface.co/malinali-app/whisper-small-wolof-onnx) (sherpa-onnx int8, prompted with English — Whisper has no `<|wo|>` token), then `malinali-app/traduction-wolof-en`, then `Xenova/opus-mt-en-fr`.
- **Written last model**: restored from `last_selected_model.json` when opening Traduction écrite; otherwise tiny Helsinki FR→EN.
- **French → Pulaar**: select in translation settings; downloads `flutter-painter/french-fula`.
- **French → Wolof** (voice / auto): same English-bridge pattern as Wolof→French. Transcribe French, Marian [`malinali-app/opus-mt-fr-en-onnx`](https://huggingface.co/malinali-app/opus-mt-fr-en-onnx) (standard `opus-mt-fr-en`, not the tiny pack), then `malinali-app/traduction-en-wolof` (Candle pack of [`LocaleNLP/eng_wolof`](https://huggingface.co/LocaleNLP/eng_wolof), prefix `>>wol<< `). The direct pack `malinali-app/traduction-fr-wolof` (BLEU 9.3, [`makhtar7186/traduction_fr_wolof`](https://huggingface.co/makhtar7186/traduction_fr_wolof)) remains in the written catalogue but is not the voice route.
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
