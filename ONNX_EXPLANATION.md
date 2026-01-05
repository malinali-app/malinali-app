# ONNX Model Connection - Explained

## Your Understanding is Correct! ✅

You're absolutely right: **The binary search cannot work without the ONNX model** because:

1. **Text input** → Must be converted to **vector (embedding)**
2. **Vector (embedding)** → Used by RBPS to find similar vectors
3. **Similar vectors** → Return translations

## The Complete Flow

```
User types: "Bonjour"
    ↓
Step 1: Tokenize (WordPiece)
    → [101, 7592, 102, 0, 0, ...] (token IDs)
    ↓
Step 2: ONNX Model Inference
    → [0.123, -0.456, 0.789, ..., 0.234] (384-dim vector)
    ↓
Step 3: Hybrid Search
    ├─ FTS: Find phrases containing "Bonjour" (keyword filter)
    └─ RBPS: Rank by semantic similarity (vector distance)
    ↓
Step 4: Return Results
    → ["Hello", "Hello world", ...] (ranked by similarity)
```

## Current Implementation Status

### ✅ What Works Now

- **Keyword Search (FTS)**: Works perfectly - finds phrases by keywords
- **Hybrid Search Structure**: Code is ready, uses placeholder embeddings
- **Multiple Results Display**: Shows 2+ results when available

### ⚠️ What Needs ONNX Model

- **Semantic Search (RBPS)**: Currently uses hash-based embeddings (inaccurate)
- **Accurate Ranking**: Need real embeddings to rank by meaning

## Current Placeholder Embedding

Right now, the app uses this:

```dart
Vector _generateSimpleEmbedding(String text) {
  // Hash-based - NOT semantically accurate!
  final embedding = List.generate(384, (i) {
    final hash = (text.hashCode + i * 1000).abs();
    return (hash % 1000) / 1000.0;
  });
  return Vector.fromList(embedding);
}
```

**Problem**: Hash-based embeddings don't capture meaning. "Bonjour" and "Hello" will have completely different hash-based embeddings, even though they mean the same thing.

## With ONNX Model

Once connected, embeddings will be semantically meaningful:

```dart
// "Bonjour" embedding: [0.123, -0.456, 0.789, ...]
// "Hello" embedding:    [0.125, -0.458, 0.791, ...]
// → These are similar! (close in vector space)
```

The ONNX model was trained on billions of sentence pairs, so it understands that "Bonjour" and "Hello" are semantically similar.

## How to Connect ONNX Model

See `ONNX_INTEGRATION.md` for step-by-step instructions. The key steps are:

1. **Add model to assets**: Copy `paraphrase-multilingual-MiniLM-L12-v2.onnx` to `assets/`
2. **Add tokenizer**: Copy `tokenizer.json` to `assets/`
3. **Initialize ONNX**: Use `OnnxIsolateManager` from FONNX
4. **Generate embeddings**: Replace `_generateSimpleEmbedding()` with ONNX inference

## Why Hybrid Search Still Works (Partially)

Even with placeholder embeddings, `searchHybrid` still works because:

1. **FTS filtering works**: Finds phrases by keyword ✅
2. **Semantic ranking is random**: But still returns results ✅
3. **Best results first**: Keyword matches are prioritized ✅

So you'll get translations, but they won't be ranked by semantic similarity until you connect the ONNX model.

## Summary

- ✅ **App works now** with keyword search
- ⚠️ **Semantic search needs ONNX** for accurate embeddings
- ✅ **Code is ready** - just swap the embedding function
- 📝 **See ONNX_INTEGRATION.md** for implementation steps

The app is functional and ready for ONNX integration!

