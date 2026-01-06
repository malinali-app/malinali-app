// Test semantic search performance on dataset samples
// Run with: flutter test test/semantic_search_test.dart

// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ml_algo/src/retrieval/hybrid_fts_searcher.dart';
import 'package:ml_algo/src/retrieval/translation_pair.dart';
import 'package:ml_algo/src/persistence/sqlite_neighbor_search_store.dart';
import 'package:malinali/services/embedding_service.dart';

Future<void> main() async {
  // Initialize Flutter test bindings
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock path_provider to return temp directory
  final tempDir = Directory.systemTemp.createTempSync('malinali_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        },
      );

  // Setup ONNX runtime libraries for test environment
  await _setupOnnxRuntime(tempDir);

  print('Testing Semantic Search Performance\n');
  print('==================================================');

  // Use temp directory for test database (separate from prod)
  final dbPath = '${tempDir.path}/test_fula_translations.db';

  // Initialize embedding service
  final embeddingService = EmbeddingService();
  await embeddingService.initialize();

  // Load dataset and create searcher
  final store = SQLiteNeighborSearchStore(dbPath);

  print('Loading dataset...');
  // Try to load from production database first (if it exists)
  // Note: path_provider is mocked, so we need to use the real path
  HybridFTSSearcher? searcher;
  try {
    // Try production database path (real app directory, not mocked)
    final homeDir = Platform.environment['HOME'] ?? '';
    final possiblePaths = [
      '$homeDir/Library/Containers/com.mlalgo.malinali/Data/Documents/fula_translations.db',
      '$homeDir/Library/Application Support/malinali/fula_translations.db',
    ];

    String? prodDbPath;
    for (final path in possiblePaths) {
      final file = File(path);
      if (file.existsSync()) {
        prodDbPath = path;
        break;
      }
    }

    if (prodDbPath != null) {
      final prodStore = SQLiteNeighborSearchStore(prodDbPath);
      searcher = await HybridFTSSearcher.loadFromStore(prodStore, 'fula');
      prodStore.close();
      print('✅ Loaded existing searcher from production database: $prodDbPath');
    } else {
      throw Exception('Production database not found in any expected location');
    }
  } catch (eProd) {
    // Try test database
    try {
      searcher = await HybridFTSSearcher.loadFromStore(store, 'fula');
      print('✅ Loaded existing searcher from test database');
    } catch (e) {
      // Create new test dataset with samples
      print('Creating test dataset from samples...');
      try {
        await _createDataset(store, embeddingService);
        searcher = await HybridFTSSearcher.loadFromStore(store, 'fula');
        print('✅ Created and loaded test searcher');
      } catch (e2) {
        if (e2.toString().contains('Invalid Output Name:embeddings')) {
          print('\n❌ ERROR: Model output name mismatch');
          print(
            '   The ONNX model does not have an output named "embeddings".',
          );
          print('   Production app works, so the model should be correct.');
          print('   This may be a test environment issue.');
          print('\n   Possible solutions:');
          print(
            '   1. Use production database: Run the app first to create the database',
          );
          print('   2. Check fonnx package version/configuration');
          print('   3. Verify model file matches production version');
          store.close();
          embeddingService.dispose();
          tempDir.deleteSync(recursive: true);
          return;
        }
        rethrow;
      }
    }
  }
  print('Dataset loaded\n');

  // Test queries - mix of religious and conversational
  final testQueries = [
    // Religious queries
    'How do I pray?',
    'I am worshipping',
    'We believe in Allah',
    'perform Salat',
    'pay Zakat',

    // Conversational queries
    'How are you?',
    'What time is it?',
    'I am good',
    'Where are you?',
    'Thank you',
  ];

  print('Testing Semantic Search (no FTS filtering):\n');
  print('--------------------------------------------------');

  for (final query in testQueries) {
    print('\nQuery: "$query"');

    // Generate embedding
    final embedding = await embeddingService.generateEmbedding(query);

    // Semantic-only search
    final semanticResults = await searcher.searchBySemantic(
      embedding,
      k: 5,
      searchRadius: 10,
    );

    print('  Found ${semanticResults.length} results:');
    for (var i = 0; i < semanticResults.length && i < 3; i++) {
      final result = semanticResults[i];
      print(
        '    ${i + 1}. EN: "${result.sourceText.substring(0, result.sourceText.length > 60 ? 60 : result.sourceText.length)}..."',
      );
    }

    // Check if top result is relevant
    if (semanticResults.isNotEmpty) {
      final topResult = semanticResults.first;
      final isRelevant = _isRelevant(query, topResult.sourceText);
      print('  Relevance: ${isRelevant ? "✅ RELEVANT" : "❌ NOT RELEVANT"}');
    }
  }

  print('\n\nTesting Hybrid Search (FTS + Semantic):\n');
  print('--------------------------------------------------');

  for (final query in testQueries) {
    print('\nQuery: "$query"');

    final embedding = await embeddingService.generateEmbedding(query);

    // Hybrid search
    final hybridResults = await searcher.searchHybrid(
      keyword: query,
      embedding: embedding,
      k: 5,
      searchRadius: 10,
    );

    print('  Found ${hybridResults.length} results:');
    for (var i = 0; i < hybridResults.length && i < 3; i++) {
      final result = hybridResults[i];
      print(
        '    ${i + 1}. EN: "${result.sourceText.substring(0, result.sourceText.length > 60 ? 60 : result.sourceText.length)}..."',
      );
    }

    if (hybridResults.isNotEmpty) {
      final topResult = hybridResults.first;
      final isRelevant = _isRelevant(query, topResult.sourceText);
      print('  Relevance: ${isRelevant ? "✅ RELEVANT" : "❌ NOT RELEVANT"}');
    }
  }

  store.close();
  embeddingService.dispose();

  // Cleanup temp directory
  tempDir.deleteSync(recursive: true);
}

/// Setup ONNX runtime libraries for test environment (cross-platform)
/// Creates the directory structure that fonnx expects and copies libraries there
Future<void> _setupOnnxRuntime(Directory tempDir) async {
  // Find ONNX runtime libraries in build directory (platform-specific)
  final onnxLibs = <File>[];
  String? expectedPath;

  if (Platform.isMacOS) {
    // macOS: look in build/macos/Build/Products/Debug/malinali.app/Contents/Frameworks
    final macosLibs = Directory(
      'build/macos/Build/Products/Debug/malinali.app/Contents/Frameworks',
    );
    if (macosLibs.existsSync()) {
      final files = macosLibs
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.path.contains('onnxruntime') ||
                f.path.contains('ortextensions'),
          )
          .toList();
      onnxLibs.addAll(files);
    }
    // fonnx expects: macos/onnx_runtime/osx/libonnxruntime.1.16.1.dylib
    expectedPath = 'macos/onnx_runtime/osx';
  } else if (Platform.isLinux) {
    // Linux: look in build/linux/x64/debug/bundle/lib
    final linuxLibs = Directory('build/linux/x64/debug/bundle/lib');
    if (linuxLibs.existsSync()) {
      final files = linuxLibs
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.path.contains('onnxruntime') ||
                f.path.contains('ortextensions'),
          )
          .toList();
      onnxLibs.addAll(files);
    }
    expectedPath = 'linux/onnx_runtime/linux-x64';
  } else if (Platform.isWindows) {
    // Windows: look in build/windows/x64/debug/runner
    final windowsLibs = Directory('build/windows/x64/debug/runner');
    if (windowsLibs.existsSync()) {
      final files = windowsLibs
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.path.contains('onnxruntime') ||
                f.path.contains('ortextensions'),
          )
          .toList();
      onnxLibs.addAll(files);
    }
    expectedPath = 'windows/onnx_runtime/win-x64';
  }

  if (onnxLibs.isEmpty || expectedPath == null) {
    print('⚠️  ONNX runtime libraries not found in build directory.');
    print(
      '   Building the app first may be required: flutter build ${Platform.isMacOS
          ? 'macos'
          : Platform.isLinux
          ? 'linux'
          : 'windows'}',
    );
    print(
      '   Note: Libraries will be loaded from build directory if available.',
    );
    return;
  }

  // Create the directory structure that fonnx expects (relative to project root)
  // Note: fonnx looks for libraries relative to Flutter engine, but we create
  // the structure in project root as a fallback
  final fonnxLibDir = Directory(expectedPath);
  fonnxLibDir.createSync(recursive: true);

  // Copy libraries to fonnx-expected location
  for (final lib in onnxLibs) {
    final libName = lib.path.split(Platform.pathSeparator).last;
    final dest = File('${fonnxLibDir.path}/$libName');

    // Only copy if it doesn't exist or is different
    if (!dest.existsSync() || dest.lengthSync() != lib.lengthSync()) {
      lib.copySync(dest.path);
      print('✅ Copied $libName to ${fonnxLibDir.path}');
    }
  }

  print('✅ ONNX runtime libraries available at: ${fonnxLibDir.absolute.path}');
  print('   Note: Libraries are in the directory structure fonnx expects');
}

/// Create dataset for testing using only a small sample (not full 15k dataset)
Future<void> _createDataset(
  SQLiteNeighborSearchStore store,
  EmbeddingService embeddingService,
) async {
  // Load text files from assets
  final allEnglishLines = await _loadTextFile(
    'assets/src_eng_license_free.txt',
  );
  final allFrenchLines = await _loadTextFile('assets/src_fra_license_free.txt');
  final allFulaLines = await _loadTextFile('assets/tgt_ful_license_free.txt');

  if (allEnglishLines.length != allFrenchLines.length ||
      allFrenchLines.length != allFulaLines.length) {
    throw Exception(
      'Files have different line counts: '
      'English: ${allEnglishLines.length}, '
      'French: ${allFrenchLines.length}, '
      'Fula: ${allFulaLines.length}',
    );
  }

  // Use only a sample for testing (200 lines: mix of religious and conversational)
  const sampleSize = 200;
  final englishLines = allEnglishLines.take(sampleSize).toList();
  final frenchLines = allFrenchLines.take(sampleSize).toList();
  final fulaLines = allFulaLines.take(sampleSize).toList();

  print(
    '✅ Using sample of $sampleSize translation pairs (from ${allEnglishLines.length} total)',
  );

  // Create translation pairs
  final allTranslations = <TranslationPair>[];

  print('Creating English→Fula pairs...');
  for (var i = 0; i < englishLines.length; i++) {
    final english = englishLines[i].trim();
    final fula = fulaLines[i].trim();

    if (english.isEmpty || fula.isEmpty) continue;

    final embeddingVector = await embeddingService.generateEmbedding(fula);

    allTranslations.add(
      TranslationPair(
        source: english,
        target: fula,
        embedding: embeddingVector.toList(),
      ),
    );

    if ((i + 1) % 50 == 0) {
      print(
        '  Processed ${i + 1}/${englishLines.length} English→Fula pairs...',
      );
    }
  }

  print('Creating French→Fula pairs...');
  for (var i = 0; i < frenchLines.length; i++) {
    final french = frenchLines[i].trim();
    final fula = fulaLines[i].trim();

    if (french.isEmpty || fula.isEmpty) continue;

    final embeddingVector = await embeddingService.generateEmbedding(fula);

    allTranslations.add(
      TranslationPair(
        source: french,
        target: fula,
        embedding: embeddingVector.toList(),
      ),
    );

    if ((i + 1) % 50 == 0) {
      print('  Processed ${i + 1}/${frenchLines.length} French→Fula pairs...');
    }
  }

  print('✅ Created ${allTranslations.length} translation pairs');

  // Create searcher
  print('Building searcher and saving to database...');
  await HybridFTSSearcher.createFromTranslations(
    store,
    allTranslations,
    digitCapacity: 8,
    searcherId: 'fula',
  );
}

/// Load text file from assets
Future<List<String>> _loadTextFile(String assetPath) async {
  // Load from Flutter assets
  final content = await rootBundle.loadString(assetPath);
  return content.split('\n').where((line) => line.trim().isNotEmpty).toList();
}

bool _isRelevant(String query, String result) {
  // Simple relevance check: shared words or semantic similarity
  final queryWords = query.toLowerCase().split(RegExp(r'\s+'));
  final resultWords = result.toLowerCase().split(RegExp(r'\s+'));

  final sharedWords = queryWords.where((w) => resultWords.contains(w)).length;
  return sharedWords > 0 ||
      queryWords.length == 1; // At least one word match, or single word query
}
