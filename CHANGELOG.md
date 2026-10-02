# Changelog

## 1.1.4 - 2 octobre 2026

### Traduction neuronale locale (MarianMT)

- Catalogue élargi : **~110+ paires bilatérales**, **~40 langues**, dont les bilatéraux africains Helsinki-NLP OPUS (haoussa, yoruba, igbo, swahili/congo, kinyarwanda, rundi, ganda, shona, lingala, nyanja, twi, ewe, kabyle, tigrinya, tiv, …).
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
- Fine-tuned French–Fula model (private) + Xenova mirrors for common pairs.
- Local Vosk speech recognition beyond French.
- No user text sent to third-party servers — fully confidential for field research and NGO work.

## 1.1.2 - 27 septembre 2026

- modèles privés

## 1.1.1 - 25 septembre 2026

- Intégration MarianMT / Candle ; ~67 modèles / ~25 langues ; Vosk au-delà du français.
