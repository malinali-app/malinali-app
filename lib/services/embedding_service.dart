// ignore_for_file: implementation_imports
import 'package:flutter/services.dart';
import 'package:fonnx/ort_minilm_isolate.dart';
import 'package:malinali/services/multilingual_tokenizer.dart';
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';
import 'package:ml_linalg/vector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:malinali/services/model_output_inspector.dart';
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
  String? _detectedOutputName; // Store the actual output name from the model

  /// Initializes the embedding service.
  ///
  /// This loads the ONNX model and tokenizer from assets.
  /// Call this once before using the service.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Copy model from assets to app directory (ONNX needs file path)
      final appDir = await getApplicationDocumentsDirectory();
      final modelFile = File('${appDir.path}/all-MiniLM-L6-v2.onnx');
      final tokenizerFile = File('${appDir.path}/tokenizer.json');

      // Copy model if not exists
      if (!await modelFile.exists()) {
        final modelData = await rootBundle.load(
          'assets/models/all-MiniLM-L6-v2.onnx',
        );
        await modelFile.writeAsBytes(modelData.buffer.asUint8List());
      }

      // Always copy tokenizer from assets to ensure we have the correct version
      // This ensures tokenizer matches the model (important when switching models)
      final tokenizerData = await rootBundle.load(
        'assets/models/tokenizer.json',
      );
      await tokenizerFile.writeAsBytes(tokenizerData.buffer.asUint8List());
      print('✅ Copied tokenizer.json from assets to app directory');

      _modelPath = modelFile.path;
      _tokenizerPath = tokenizerFile.path;

      // Load tokenizer
      _tokenizer = await MultilingualTokenizerLoader.loadTokenizer(
        _tokenizerPath!,
        maxInputTokens: 128,
      );

      // Check model output name for informational purposes only
      // Don't fail here - let fonnx handle it if there's a real issue
      // Skip on Android since FFI inspection doesn't work there
      if (!Platform.isAndroid) {
        try {
          final outputNames = ModelOutputInspector.getAllOutputNames(_modelPath!);
          print('Model output names: $outputNames');
          
          // Store the first output name for error messages later
          if (outputNames.isNotEmpty) {
            _detectedOutputName = outputNames.first;
            
            // Just log compatibility, don't throw
            final hasEmbeddings = outputNames.contains('embeddings');
            final hasSentenceEmbedding = outputNames.contains('sentence_embedding');
            
            if (hasEmbeddings) {
              print('✅ Model has "embeddings" output');
            } else if (hasSentenceEmbedding) {
              print('✅ Model has "sentence_embedding" output');
            } else {
              print('ℹ️  Model output: ${outputNames.first} (will try to use it)');
            }
          }
        } catch (e) {
          print('⚠️  Could not inspect model output names: $e');
          // Continue - don't fail initialization
        }
      } else {
        print('ℹ️  Skipping model output inspection on Android (uses platform-specific implementation)');
      }

      // Initialize ONNX isolate manager
      // On Android, this uses platform-specific implementation, not FFI
      _isolateManager = OnnxIsolateManager();
      try {
        await _isolateManager!.start(OnnxIsolateType.miniLm);
      } catch (e) {
        final errorStr = e.toString();
        if (errorStr.contains('Android runs using a platform-specific implementation')) {
          // This is expected on Android - the isolate should still work
          // The error might be from initialization checks, but the actual inference should work
          print('⚠️  ONNX isolate initialization warning (expected on Android): $e');
          // Continue - the isolate manager should still work for inference
        } else {
          // Re-throw if it's a different error
          rethrow;
        }
      }

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
    try {
      // Use detected output name if available, otherwise let fonnx use its default
      // On Android, don't pass outputName since we can't detect it (FFI not available)
      final embedding = await _isolateManager!.sendInference(
        _modelPath!,
        paddedTokens.take(maxLength).toList(),
        outputName: Platform.isAndroid ? null : _detectedOutputName, // Skip on Android
      );

      // Convert to Vector (take first 384 dimensions)
      return Vector.fromList(
        embedding.take(384).map((e) => e.toDouble()).toList(),
      );
    } catch (e) {
      final errorStr = e.toString();
      
      // On Android, the fonnx package should use method channels automatically
      // If we still get FFI errors, it means the fix didn't work or wasn't picked up
      if (Platform.isAndroid && errorStr.contains('Android runs using a platform-specific implementation')) {
        throw Exception(
          'ONNX inference failed on Android.\n'
          'Error: $e\n\n'
          'The fonnx package should automatically use method channels on Android instead of FFI isolates.\n'
          'This error suggests the fix may not have been applied. Please:\n'
          '1. Ensure you have the latest version of the fonnx fork\n'
          '2. Run: flutter clean && flutter pub get\n'
          '3. Rebuild the app'
        );
      }
      
      // Check if this is an "Invalid Output Name" error (for either "embeddings" or "sentence_embedding")
      if (errorStr.contains('Invalid Output Name')) {
        // Use detected output name if available, otherwise get it again
        List<String> outputNames;
        if (_detectedOutputName != null) {
          outputNames = [_detectedOutputName!];
        } else {
          // On Android, we can't inspect model outputs, so skip
          if (Platform.isAndroid) {
            outputNames = ['unknown'];
          } else {
            try {
              outputNames = ModelOutputInspector.getAllOutputNames(_modelPath!);
            } catch (inspectError) {
              outputNames = ['unknown'];
            }
          }
        }
        
        // Determine which output name the fonnx fork expects
        String expectedOutput;
        String forkName;
        String recommendedFork;
        if (errorStr.contains('sentence_embedding')) {
          expectedOutput = 'sentence_embedding';
          forkName = 'malinali-app/fonnx';
          recommendedFork = 'Telosnex/fonnx (default)';
        } else if (errorStr.contains('embeddings')) {
          expectedOutput = 'embeddings';
          forkName = 'default fonnx (Telosnex/fonnx)';
          recommendedFork = 'malinali-app/fonnx';
        } else {
          expectedOutput = 'unknown';
          forkName = 'fonnx';
          recommendedFork = 'Check model output name';
        }
        
        final actualOutput = outputNames.isNotEmpty ? outputNames.first : 'unknown';
        
        throw Exception(
          'ONNX model output name mismatch!\n\n'
          'Current fonnx fork: $forkName\n'
          'Expected output name: "$expectedOutput"\n'
          'Your model has: "$actualOutput"\n\n'
          'Quick Fix:\n'
          '1. Open pubspec.yaml\n'
          '2. Switch to the correct fonnx fork:\n'
          '   - If your model has "embeddings": use Telosnex/fonnx (default)\n'
          '   - If your model has "sentence_embedding": use malinali-app/fonnx\n'
          '3. Run: flutter pub get\n'
          '4. Restart the app\n\n'
          'Alternative: Re-export your model with output name "$expectedOutput"\n\n'
          'All model outputs: ${outputNames.join(", ")}\n'
          'Original error: $e',
        );
      }
      rethrow;
    }
  }

  /// Disposes resources.
  void dispose() {
    _isolateManager?.stop();
    _isolateManager = null;
    _tokenizer = null;
    _isInitialized = false;
  }
}
