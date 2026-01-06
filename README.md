# Malinali - Local Translation App

A simple Flutter app for local translation using hybrid FTS + semantic search.

![offline_translator_diagram.png](offline_translator_diagram.png)


TODO: please dig how the multilingual embedding model is clustering our phrases

TODO: explain how this lightweight app is different from the other, such as opennmt, ctranslate2, INMT-lite

offline first, mobile friendly (flutter)

## Features

- **Text Editor**: Multi-line text input using `re_editor`
- **Hybrid Search**: Combines keyword (FTS) and semantic (RBPS) search
- **Language Swap**: Easy language permutation via AppBar button
- **Offline**: All translations stored locally in SQLite
- **Fast**: Sub-20ms translation queries

## Getting Started

### Prerequisites

- Flutter SDK
- The `ml_algo` package (path dependency to parent directory)

### Running the App

```bash
cd malinali
flutter pub get
flutter run
```

## Current Implementation

- **Languages**: French ↔ English
- **Translation Method**: Keyword search (FTS)
- **Sample Data**: 15 common phrases pre-loaded

## Next Steps

1. **Integrate ONNX Model**: Connect to FONNX for real embedding generation
2. **Add More Languages**: Extend to French-Fula translations
3. **Semantic Search**: Use `searchHybrid()` with embeddings for better accuracy
4. **Load Custom Vocabulary**: Use your French-Fula vocab.txt

## Architecture

```
TranslationScreen
├── Input Editor (re_editor)
├── Output Editor (read-only)
├── FloatingActionButton (translate)
└── AppBar (language swap)

HybridFTSSearcher
├── FTS (keyword search)
└── RBPS (semantic search)
```

## Notes

- Database stored in app documents directory
- Sample embeddings are placeholder (use ONNX model in production)
- Translation pairs are created on first launch
