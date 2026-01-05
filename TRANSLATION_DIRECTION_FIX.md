# Translation Direction Issue - Analysis & Fix

## The Problem

- ✅ English → French works: "I am fine" → "Je vais bien"
- ❌ French → English fails: "Je vais bien" → "No translation found"

## Root Cause

The issue is in how embeddings are stored and searched:

1. **Storage**: Embeddings are generated from **English text** (target language)
   ```dart
   // Line 116 in main.dart
   final embeddingVector = await embeddingService.generateEmbedding(pair[1]); // English
   ```

2. **Search French→English**:
   - Query: "Je vais bien" (French)
   - FTS: Searches for "Je vais bien" in `french_text` column ✅ (should work)
   - Semantic: Compares French embedding vs English embeddings ❌ (mismatch!)

3. **Search English→French**:
   - Query: "I am fine" (English)
   - FTS: Searches for "I am fine" in `english_text` column ✅
   - Semantic: Compares English embedding vs English embeddings ✅ (match!)

## The Fix

We need to generate embeddings for **both languages** or use a different strategy:

### Option 1: Store embeddings for source language (French)
Change line 116 to generate embeddings from French:
```dart
final embeddingVector = await embeddingService.generateEmbedding(pair[0]); // French
```

**Pros**: Works for French→English
**Cons**: Breaks English→French

### Option 2: Store embeddings for both languages (Best)
Store two embeddings per translation pair:
- French embedding (for French→English queries)
- English embedding (for English→French queries)

### Option 3: Use semantic search only (Current workaround)
Since the model is multilingual, French and English embeddings should be semantically similar. The issue might be FTS filtering too strictly.

## Quick Test

Run the app and check the debug output:
- `DEBUG: Keyword search found X results` - Shows if FTS is working
- `DEBUG: Hybrid search found X results` - Shows if hybrid search works

If keyword search finds results but hybrid doesn't, the issue is semantic ranking.
If keyword search finds nothing, the issue is FTS query format.

