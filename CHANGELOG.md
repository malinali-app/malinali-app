# Changelog

## 1.1.9 - 12 octobre 2026

- feat: whisper onnx through sherpa_onnx
  - Whisper ONNX generic packs via sherpa-onnx (not whisper.cpp):
    [`malinali-app/whisper-tiny-onnx`](https://huggingface.co/malinali-app/whisper-tiny-onnx) (~103 Mo),
    [`malinali-app/whisper-small-onnx`](https://huggingface.co/malinali-app/whisper-small-onnx) (~375 Mo)
- feat: marianMT onnx through self-made package 
  - No Candle at launch. Voice home downloads Whisper only; Marian ONNX loads on first turn
  - Voice FR/EN/Wolof hops use ONNX ids (`opus-mt_tiny_fra-eng-onnx`, `opus-mt-en-fr-onnx`, `traduction-*-onnx`)
  - Android NDK `libmarian_onnx.so` (ORT AAR). Candle stays for written catalog / BYO
  - Windows/Android boot translator: [`malinali-app/opus-mt_tiny_fra-eng-onnx`](https://huggingface.co/malinali-app/opus-mt_tiny_fra-eng-onnx)
  - MarianMT ONNX native adapter: later `decoder_with_past` steps do not send `encoder_hidden_states`; encoder KVs stay in the past map

## 1.1.5 & 1.1.6 - 3 octobre 2026

- added aptabase
- switched default French-English model to **tiny** version (25M params, ~75MB) for faster first launch and lower footprint.

## 1.1.4 - 2 octobre 2026

### Traduction neuronale locale (MarianMT)

- Catalogue élargi : **~110+ modèles**, **~40 langues**, dont haoussa, yoruba, igbo, swahili/congo, kinyarwanda, rundi, ganda, shona, lingala, nyanja, twi, ewe, kabyle, tigrinya, tiv...
- Packs Candle publics sous [`malinali-app`](https://huggingface.co/malinali-app) (`config` + `safetensors` + tokenizers) — scores BLEU OPUS affichés en `BLEU xx.x / 100` dans Paramètres → Traduction.
- Modèle **français → peul (fula)** privé toujours disponible ; Xenova Opus-MT pour le reste des paires européennes / asiatiques courantes.

### Transcription audio (Vosk)

- Reconnaissance vocale locale avec **Vosk**, au-delà du français uniquement.
- Utile pour collecter, transcrire et annoter des données orales hors ligne (enquêtes, ateliers, missions terrain).

### Confidentialité & usage ONG / recherche

- Aucun envoi du texte utilisateur vers des serveurs tiers : **100 % confidentiel**, adapté aux contextes sensibles (santé, droits, humanitaire).
- Conçu pour les équipes qui travaillent avec des langues à faibles ressources : dictionnaires, glossaires et modèles utilisables **hors ligne**, y compris sur appareils modestes.
- Outil libre pour la documentation linguistique, la médiation, la formation et les projets de recherche collaborative.

---

### English (summary)

- Local MarianMT via Rust Candle; ~110+ bilateral pairs across ~40 languages, including African Helsinki OPUS packs hosted at malinali-app (BLEU shown as `/ 100`).
- Switched default FR-EN model to **tiny** variant (25M params) to reduce app footprint.
- Fine-tuned French–Fula model (private) + Xenova mirrors for common pairs.
- Local Vosk speech recognition beyond French.
- No user text sent to third-party servers — fully confidential for field research and NGO work.

## 1.1.2 - 27 septembre 2026

- modèles privés

## 1.1.1 - 25 septembre 2026

- Intégration MarianMT / Candle ; ~67 modèles / ~25 langues ; Vosk au-delà du français.
