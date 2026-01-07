// ignore_for_file: implementation_imports
import 'dart:io';
import 'package:ml_algo/src/persistence/sqlite_neighbor_search_store.dart';
import 'package:ml_algo/src/retrieval/hybrid_fts_searcher.dart';
import 'package:ml_algo/src/retrieval/translation_pair.dart';
import 'package:malinali/services/embedding_service.dart';
import 'package:path_provider/path_provider.dart';

/// Standalone function to generate embeddings from source and target text files.
///
/// This function:
/// 1. Loads two text files (one translation per line)
/// 2. Validates that both files have the same number of lines
/// 3. Generates embeddings using ONNX model for the source language
/// 4. Creates HybridFTSSearcher and saves to SQLite database
///
/// Parameters:
/// - [sourceFilePath]: Path to source language file (e.g., French)
/// - [targetFilePath]: Path to target language file (e.g., Fula)
/// - [dbPath]: Path where the SQLite database will be created
/// - [searcherId]: Identifier for the searcher in the database (default: 'fula')
/// - [onProgress]: Optional callback for progress updates (current, total)
///
/// Throws [Exception] if:
/// - Files don't exist
/// - Files have different line counts
/// - Embedding generation fails
Future<void> generateEmbeddingsFromFiles({
  required String sourceFilePath,
  required String targetFilePath,
  required String dbPath,
  String searcherId = 'fula',
  void Function(int current, int total)? onProgress,
}) async {
  // Step 1: Load text files
  print('Loading text files...');
  final sourceFile = File(sourceFilePath);
  final targetFile = File(targetFilePath);

  if (!await sourceFile.exists()) {
    throw Exception('Source file not found: $sourceFilePath');
  }
  if (!await targetFile.exists()) {
    throw Exception('Target file not found: $targetFilePath');
  }

  final sourceContent = await sourceFile.readAsString();
  final targetContent = await targetFile.readAsString();

  final sourceLines = sourceContent
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final targetLines = targetContent
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  // Step 2: Validate line counts
  if (sourceLines.length != targetLines.length) {
    throw Exception(
      'Files have different line counts: '
      'Source: ${sourceLines.length}, Target: ${targetLines.length}',
    );
  }

  print('✅ Loaded ${sourceLines.length} translation pairs');

  // Step 3: Initialize EmbeddingService
  print('Initializing embedding service...');
  final embeddingService = EmbeddingService();
  await embeddingService.initialize();

  // Step 4: Set up SQLite store
  final store = SQLiteNeighborSearchStore(dbPath);

  // Step 5: Create translation pairs and generate embeddings
  print('Generating embeddings...');
  final translations = <TranslationPair>[];

  for (var i = 0; i < sourceLines.length; i++) {
    final source = sourceLines[i];
    final target = targetLines[i];

    if (source.isEmpty || target.isEmpty) continue;

    // Generate embedding for source language (we search from source)
    final embeddingVector = await embeddingService.generateEmbedding(source);

    translations.add(
      TranslationPair(
        source: source,
        target: target,
        embedding: embeddingVector.toList(),
      ),
    );

    // Progress callback
    if (onProgress != null) {
      onProgress(i + 1, sourceLines.length);
    }

    // Progress indicator
    if ((i + 1) % 500 == 0) {
      print('  Processed ${i + 1}/${sourceLines.length} pairs...');
    }
  }

  // Step 6: Create searcher and save to database
  print('Building searcher and saving to database...');
  await HybridFTSSearcher.createFromTranslations(
    store,
    translations,
    digitCapacity: 8,
    searcherId: searcherId,
  );

  // Clean up
  embeddingService.dispose();
  store.close();

  print('✅ Created ${translations.length} translation pairs');
  print('✅ Database saved to: $dbPath');
}

