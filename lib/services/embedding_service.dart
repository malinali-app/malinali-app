// ignore_for_file: implementation_imports
import 'package:flutter/services.dart';
import 'package:fonnx/ort_minilm_isolate.dart';
import 'package:malinali/services/multilingual_tokenizer.dart';
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';
import 'package:ml_linalg/vector.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// Service for generating text embeddings using the ONNX model.
///
/// This service encapsulates all the complexity of:
/// - Loading the ONNX model
/// - Loading the tokenizer
/// - Tokenizing text
/// - Running ONNX inference
/// - Returning embeddings as vectors
///
/// Usage:
/// ```dart
/// final service = EmbeddingService();
/// await service.initialize();
/// final embedding = await service.generateEmbedding('Bonjour');
/// ```
class EmbeddingService {
  OnnxIsolateManager? _isolateManager;
  WordpieceTokenizer? _tokenizer;
  String? _modelPath;
  String? _tokenizerPath;
  bool _isInitialized = false;

  /// Initializes the embedding service.
  ///
  /// This loads the ONNX model and tokenizer from assets.
  /// Call this once before using the service.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Copy model from assets to app directory (ONNX needs file path)
      final appDir = await getApplicationDocumentsDirectory();
      final modelFile = File(
        '${appDir.path}/paraphrase-multilingual-MiniLM-L12-v2.onnx',
      );
      final tokenizerFile = File('${appDir.path}/tokenizer.json');

      // Copy model if not exists
      if (!await modelFile.exists()) {
        final modelData = await rootBundle.load(
          'assets/models/paraphrase-multilingual-MiniLM-L12-v2.onnx',
        );
        await modelFile.writeAsBytes(modelData.buffer.asUint8List());
      }

      // Copy tokenizer if not exists
      if (!await tokenizerFile.exists()) {
        final tokenizerData = await rootBundle.load(
          'assets/models/tokenizer.json',
        );
        await tokenizerFile.writeAsBytes(tokenizerData.buffer.asUint8List());
      }

      _modelPath = modelFile.path;
      _tokenizerPath = tokenizerFile.path;

      // Load tokenizer
      _tokenizer = await MultilingualTokenizerLoader.loadTokenizer(
        _tokenizerPath!,
        maxInputTokens: 128,
      );

      // Initialize ONNX isolate manager
      _isolateManager = OnnxIsolateManager();
      await _isolateManager!.start(OnnxIsolateType.miniLm);

      _isInitialized = true;
    } catch (e) {
      throw Exception('Failed to initialize EmbeddingService: $e');
    }
  }

  /// Generates a 384-dimensional embedding vector from text.
  ///
  /// This method:
  /// 1. Tokenizes the text using WordPiece tokenization
  /// 2. Runs ONNX model inference
  /// 3. Returns the embedding as a Vector
  ///
  /// Throws [StateError] if service is not initialized.
  Future<Vector> generateEmbedding(String text) async {
    if (!_isInitialized ||
        _tokenizer == null ||
        _isolateManager == null ||
        _modelPath == null) {
      throw StateError(
        'EmbeddingService not initialized. Call initialize() first.',
      );
    }

    // Tokenize text
    final tokenized = _tokenizer!.tokenize(text);
    if (tokenized.isEmpty) {
      throw Exception('Tokenization returned empty result for: $text');
    }

    // Get tokens from first chunk
    final tokens = tokenized.first.tokens;

    // Pad or truncate to max length (128 for this model)
    final maxLength = 128;
    final paddedTokens = <int>[];
    if (tokens.length > maxLength) {
      // Truncate: keep [CLS] and first maxLength-2 tokens, then [SEP]
      paddedTokens.addAll(tokens.take(maxLength - 1));
      if (paddedTokens.last != _tokenizer!.endToken) {
        paddedTokens[paddedTokens.length - 1] = _tokenizer!.endToken;
      }
    } else {
      paddedTokens.addAll(tokens);
      // Pad to maxLength
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

  /// Disposes resources.
  void dispose() {
    _isolateManager?.stop();
    _isolateManager = null;
    _tokenizer = null;
    _isInitialized = false;
  }
}
