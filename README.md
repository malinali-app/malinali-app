# Malinali - Local Translation App

An offline-first Flutter app for local translation using hybrid FTS + semantic search.

![offline_translator_diagram.png](offline_translator_diagram.png)

If distance < 0.1, show "Translation not found" (poor clustering).

## Approach: Frugal, Open Source, Pragmatic

Malinali takes a **retrieval-based translation** approach rather than generative neural translation. This makes it fundamentally different from solutions like OpenNMT, CTranslate2, or INMT-lite:

This approach is **imperfect but pragmatic**:
- ✅ **Works offline**: All data stored locally, no API calls
- ✅ **Mobile-friendly**: Flutter app, runs smoothly on low-end devices
- ✅ **Fast**: Sub-20ms queries using SQLite FTS + approximate nearest neighbor search
- ✅ **Open source**: Full transparency, easy to extend and customize
- ⚠️ **Limited to training data**: Can only translate phrases seen in the corpus
- ⚠️ **No context awareness**: Each phrase translated independently
- ⚠️ **Requires quality corpus**: Translation quality depends on dataset quality

**When to use Malinali:**
- Domain-specific translations (e.g., medical, legal, technical)
- Low-resource languages with limited training data
- Offline-first requirements
- Privacy-sensitive applications
- Resource-constrained environments

**When to use neural translation:**
- General-purpose translation with high coverage
- Context-aware, fluent generation
- Handling unseen phrases and creative language

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
- Fula Translation pairs are created on first launch
