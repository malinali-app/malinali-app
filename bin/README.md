# Embedding Generation Tools

This folder contains command-line tools for generating translation embeddings.

## Current Status

The embedding generation requires Flutter/ONNX integration, so it's currently done in the app itself. The CLI tool structure is ready for future implementation.

## Usage (Future)

```bash
# Generate embeddings for English/French → Fula
dart run bin/generate_embeddings.dart \
  --english assets/src_eng_license_free.txt \
  --french assets/src_fra_license_free.txt \
  --fula assets/tgt_ful_license_free.txt \
  --output fula_translations.db \
  --searcher-id fula
```

## Current Workflow

1. Run the Flutter app: `flutter run`
2. App automatically generates database on first launch
3. Database saved to: `{appDocuments}/fula_translations.db`

## Future: Standalone CLI Tool

To make this a standalone CLI tool, we'd need to:
1. Extract EmbeddingService to work without Flutter
2. Handle ONNX model loading in pure Dart
3. Support command-line arguments

This would allow:
- Generating embeddings during CI/CD
- Pre-building databases for distribution
- Batch processing multiple datasets

