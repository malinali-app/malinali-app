# Changelog

## 1.1.2 - 27 septembre 2026

- modèles privés

## 1.1.1 - 25 septembre 2026

### Traduction neuronale locale (MarianMT)

- Intégration de **MarianMT** via un pont Rust / Candle : inférence sur l’appareil, sans cloud.
- Plus de **67 modèles** MarianMT ouverts, couvrant environ **25 langues** — au-delà du peul (fula).
- Modèle **français ↔ peul (fula)** affinés à partir d’Helsinki-NLP OPUS (pipeline Python) — travail en cours, destiné au terrain et à la recherche.

### Transcription audio (Vosk)

- Reconnaissance vocale locale avec **Vosk**, désormais au-delà du français uniquement.
- Utile pour collecter, transcrire et annoter des données orales hors ligne (enquêtes, ateliers, missions terrain).

### Confidentialité & usage ONG / recherche

- Aucun envoi du texte utilisateur vers des serveurs tiers : **100 % confidentiel**, adapté aux contextes sensibles (santé, droits, humanitaire).
- Conçu pour les équipes qui travaillent avec des langues à faibles ressources : dictionnaires, glossaires et modèles utilisables **hors ligne**, y compris sur appareils modestes.
- Outil libre pour la documentation linguistique, la médiation, la formation et les projets de recherche collaborative.

---

### English (summary)

- Local MarianMT translation via Rust Candle bridge; 67+ open models across ~25 languages.
- Fine-tuned French–Fula model (Helsinki OPUS / Python) — WIP.
- Local Vosk speech recognition beyond French.
- No user text sent to third-party servers — fully confidential for field research and NGO work.
