import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/embedding_service.dart';
import 'package:malinali/services/model_output_inspector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'dart:io';

void main() {
  // Initialize Flutter test bindings
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Mock path_provider for tests
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              final tempDir = Directory.systemTemp.createTempSync('malinali_test_');
              return tempDir.path;
            }
            return null;
          },
        );
  });
  group('EmbeddingService', () {
    test('should detect model output names', () async {
      // Get the model path
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/all-MiniLM-L6-v2.onnx';
      
      // Check if model exists (it should be copied during app initialization)
      final modelFile = File(modelPath);
      if (!await modelFile.exists()) {
        // Try assets path
        final assetsModelPath = 'assets/models/all-MiniLM-L6-v2.onnx';
        final assetsFile = File(assetsModelPath);
        if (!await assetsFile.exists()) {
          print('⚠️  Model file not found at $modelPath or $assetsModelPath');
          print('   Skipping test - model needs to be available');
          return;
        }
      }
      
      // Inspect model output names
      print('\n📋 Inspecting model output names...');
      final outputNames = ModelOutputInspector.getAllOutputNames(modelPath);
      print('Model output names: $outputNames');
      
      expect(outputNames, isNotEmpty, reason: 'Model should have at least one output');
      print('✅ First output name: ${outputNames.first}');
    });

    test('should initialize and generate embedding', () async {
      final service = EmbeddingService();
      
      try {
        print('\n🔧 Initializing EmbeddingService...');
        await service.initialize();
        print('✅ Service initialized');
        
        print('\n🧪 Testing embedding generation...');
        final testText = 'Hello world';
        final embedding = await service.generateEmbedding(testText);
        
        print('✅ Embedding generated!');
        print('   Dimensions: ${embedding.length}');
        print('   First 5 values: ${embedding.take(5).toList()}');
        
        expect(embedding.length, 384, reason: 'Embedding should be 384-dimensional');
        expect(embedding.any((v) => v != 0), isTrue, reason: 'Embedding should have non-zero values');
        
        print('\n✅ Test passed! Embedding service works correctly.');
      } catch (e, stackTrace) {
        print('\n❌ Test failed with error:');
        print('Error: $e');
        print('Stack trace: $stackTrace');
        
        // Provide helpful debugging info
        if (e.toString().contains('Invalid Output Name')) {
          print('\n🔍 Debugging output name issue:');
          try {
            final appDir = await getApplicationDocumentsDirectory();
            final modelPath = '${appDir.path}/all-MiniLM-L6-v2.onnx';
            final outputNames = ModelOutputInspector.getAllOutputNames(modelPath);
            print('   Model has outputs: $outputNames');
            print('   Expected by fonnx: "embeddings" (default) or "sentence_embedding" (malinali-app fork)');
            print('   Fix: Update fonnx fork to use: ${outputNames.first}');
          } catch (inspectError) {
            print('   Could not inspect model: $inspectError');
          }
        }
        
        rethrow;
      } finally {
        service.dispose();
      }
    });

    test('should handle multiple embeddings', () async {
      final service = EmbeddingService();
      
      try {
        await service.initialize();
        
        final texts = ['Hello', 'World', 'Test'];
        final embeddings = <List<double>>[];
        
        for (final text in texts) {
          final embedding = await service.generateEmbedding(text);
          embeddings.add(embedding.toList());
        }
        
        expect(embeddings.length, 3);
        expect(embeddings.every((e) => e.length == 384), isTrue);
        
        // Embeddings should be different
        final first = embeddings[0];
        final second = embeddings[1];
        expect(first, isNot(equals(second)), reason: 'Different texts should produce different embeddings');
        
        print('✅ Generated ${embeddings.length} embeddings successfully');
      } finally {
        service.dispose();
      }
    });
  });
}

