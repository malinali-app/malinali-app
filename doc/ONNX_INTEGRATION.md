# ONNX Model Integration Guide

## Why We Need the ONNX Model

You're absolutely correct! The **Random Binary Projection Search (RBPS)** algorithm works with **vectors**, not text. Here's the flow:

```
User Input: "Bonjour"
    ↓
Step 1: Tokenize → [101, 7592, 102, 0, 0, ...] (token IDs)
    ↓
Step 2: ONNX Model Inference → [0.123, -0.456, 0.789, ...] (384-dim vector)
    ↓
Step 3: RBPS Search → Find similar vectors in database
    ↓
Step 4: Return translations
```

**Without the ONNX model**, we can't convert text to embeddings, so semantic search won't work properly.

## Current Implementation

Right now, the app uses a **simple hash-based embedding** as a placeholder:

```dart
Vector _generateSimpleEmbedding(String text) {
  // Placeholder - creates embedding from text hash
  final embedding = List<double>.generate(384, (i) {
    final hash = (text.hashCode + i * 1000).abs();
    return (hash % 1000) / 1000.0;
  });
  return Vector.fromList(embedding);
}
```

This works for testing, but **won't give accurate semantic similarity**.

## How to Connect the ONNX Model

### Step 1: Add FONNX Dependency

Already done! The app has access to `fonnx` via the parent `ml_algo` package.

### Step 2: Initialize ONNX Model

```dart
import 'package:fonnx/ort_minilm_isolate.dart';
import 'package:ml_algo/src/retrieval/multilingual_tokenizer.dart';
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';

class TranslationService {
  OnnxIsolateManager? _isolateManager;
  WordpieceTokenizer? _tokenizer;
  String? _modelPath;

  Future<void> initialize() async {
    // Load tokenizer
    final tokenizerPath = 'assets/tokenizer.json';
    _tokenizer = await MultilingualTokenizerLoader.loadTokenizer(tokenizerPath);
    
    // Initialize ONNX isolate manager
    _isolateManager = OnnxIsolateManager();
    await _isolateManager!.start(OnnxIsolateType.miniLm);
    
    // Model path (copy ONNX model to assets)
    _modelPath = 'assets/all-MiniLM-L6-v2.onnx';
  }

  Future<Vector> generateEmbedding(String text) async {
    if (_tokenizer == null || _isolateManager == null || _modelPath == null) {
      throw StateError('TranslationService not initialized');
    }

    // Tokenize
    final tokenized = _tokenizer!.tokenize(text);
    if (tokenized.isEmpty) {
      throw Exception('Tokenization failed');
    }
    
    final tokens = tokenized.first.tokens;
    
    // Pad/truncate to 128 tokens
    final maxLength = 128;
    final paddedTokens = <int>[];
    if (tokens.length > maxLength) {
      paddedTokens.addAll(tokens.take(maxLength - 1));
      if (paddedTokens.last != _tokenizer!.endToken) {
        paddedTokens[paddedTokens.length - 1] = _tokenizer!.endToken;
      }
    } else {
      paddedTokens.addAll(tokens);
      while (paddedTokens.length < maxLength) {
        paddedTokens.add(0); // pad token
      }
    }

    // Run ONNX inference
    final embedding = await _isolateManager!.sendInference(
      _modelPath!,
      paddedTokens.take(maxLength).toList(),
    );

    // Convert to Vector (take first 384 dimensions)
    return Vector.fromList(
      embedding.take(384).map((e) => e.toDouble()).toList(),
    );
  }
}
```

### Step 3: Update Translation Method

```dart
Future<void> _translate() async {
  // Generate real embedding from ONNX model
  final queryEmbedding = await _translationService.generateEmbedding(inputText);
  
  // Use hybrid search
  final results = await _searcher!.searchHybrid(
    keyword: inputText,
    embedding: queryEmbedding,
    k: 5,
  );
  
  // Display results...
}
```

## What Happens Without ONNX Model?

**Current (hash-based embeddings):**
- ✅ Keyword search works (FTS)
- ⚠️ Semantic search works but is inaccurate (hash ≠ meaning)
- ⚠️ Hybrid search: keyword filtering works, but semantic ranking is random

**With ONNX Model:**
- ✅ Keyword search works (FTS)
- ✅ Semantic search works accurately (embeddings capture meaning)
- ✅ Hybrid search: keyword filtering + accurate semantic ranking

## Summary

**Your understanding is correct:**
1. Text → Tokenize → ONNX Model → Embedding Vector (384-dim)
2. Embedding Vector → RBPS → Find similar vectors
3. Similar vectors → Return translations

**Current status:**
- App works with placeholder embeddings
- Ready to connect ONNX model
- Just need to add the embedding generation service

The app is structured to easily swap `_generateSimpleEmbedding()` with real ONNX-based embedding generation.

