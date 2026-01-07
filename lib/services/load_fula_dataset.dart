// ignore_for_file: implementation_imports
import 'package:flutter/services.dart';
import 'package:ml_algo/src/persistence/sqlite_neighbor_search_store.dart';
import 'package:ml_algo/src/retrieval/hybrid_fts_searcher.dart';
import 'package:ml_algo/src/retrieval/translation_pair.dart';
import 'package:malinali/services/embedding_service.dart';
import 'package:path_provider/path_provider.dart';

/// Loads a text file from assets, one line per entry
Future<List<String>> loadTextFileFromAssets(String assetPath) async {
  final content = await rootBundle.loadString(assetPath);
  return content.split('\n').where((line) => line.trim().isNotEmpty).toList();
}

/// Loads English-Fula and French-Fula translation pairs from text files.
///
/// Creates ONE searcher that handles:
/// - English → Fula
/// - French → Fula
///
/// Future: Can add Spanish → Fula to the same searcher, or create a new one.
///
/// The "searcher ID" is just a name to identify this searcher in the database.
/// You can have multiple searchers (e.g., 'english-french-fula', 'spanish-fula')
/// in the same database file.
///
/// NOTE: This is a convenience function for development. For production,
/// consider pre-generating the database and including it in app assets.
Future<void> loadFrenchFulaDataset() async {
  // Step 1: Initialize EmbeddingService
  final embeddingService = EmbeddingService();
  await embeddingService.initialize();

  // Step 2: Load the three text files
  print('Loading text files from assets...');
  // final englishLines = await loadTextFileFromAssets(
  //   'assets/src_fra.txt',
  // );
  final frenchLines = await loadTextFileFromAssets('assets/src_fra.txt');
  final fulaLines = await loadTextFileFromAssets('assets/tgt_ful.txt');

  // Verify all files have the same number of lines
  if (frenchLines.length != fulaLines.length) {
    throw Exception(
      'Files have different line counts: '
      //'English: ${englishLines.length}, '
      'French: ${frenchLines.length}, '
      'Fula: ${fulaLines.length}',
    );
  }

  print('✅ Loaded ${frenchLines.length} translation pairs');

  // Step 3: Set up SQLite store
  final appDir = await getApplicationDocumentsDirectory();
  final dbPath = '${appDir.path}/fula_translations.db';
  final store = SQLiteNeighborSearchStore(dbPath);

  // Step 4: Create translation pairs for BOTH English→Fula and French→Fula
  // We store embeddings for Fula (target language) so we can search from either source
  //
  // Schema: TranslationPair uses generic names:
  // - source = source text (can be English or French)
  // - target = target text (Fula)
  final englishTranslations = <TranslationPair>[]; // not used
  final frenchTranslations = <TranslationPair>[];

  // print('Creating English→Fula pairs...');
  // for (var i = 0; i < englishLines.length; i++) {
  //   final english = englishLines[i].trim();
  //   final fula = fulaLines[i].trim();

  //   if (english.isEmpty || fula.isEmpty) continue;

  //   // Generate embedding for Fula (target language)
  //   final embeddingVector = await embeddingService.generateEmbedding(fula);

  //   englishTranslations.add(
  //     TranslationPair(
  //       source: english, // Source: English
  //       target: fula, // Target: Fula
  //       embedding: embeddingVector.toList(),
  //     ),
  //   );

  //   // Progress indicator
  //   if ((i + 1) % 500 == 0) {
  //     print(
  //       '  Processed ${i + 1}/${englishLines.length} English→Fula pairs...',
  //     );
  //   }
  // }

  print('Creating French→Fula pairs...');
  for (var i = 0; i < frenchLines.length; i++) {
    final french = frenchLines[i].trim();
    final fula = fulaLines[i].trim();

    if (french.isEmpty || fula.isEmpty) continue;

    // Generate embedding for French (source language)
    // We search from French, so we need to compare French embeddings with French embeddings
    final embeddingVector = await embeddingService.generateEmbedding(french);

    frenchTranslations.add(
      TranslationPair(
        source: french, // Source: French
        target: fula, // Target: Fula
        embedding: embeddingVector.toList(),
      ),
    );

    // Progress indicator
    if ((i + 1) % 500 == 0) {
      print('  Processed ${i + 1}/${frenchLines.length} French→Fula pairs...');
    }
  }

  // Step 5: Create searcher and save to database
  // Combine all translations into one searcher
  print('Building searcher and saving to database...');

  final allTranslations = [...englishTranslations, ...frenchTranslations];

  // Create searcher (ml_algo uses generic source/target names)
  await HybridFTSSearcher.createFromTranslations(
    store,
    allTranslations,
    digitCapacity: 8,
    searcherId: 'fula',
  );
  // Note: createFromTranslations already saves to database automatically

  // Clean up
  embeddingService.dispose();
  store.close();
  print('✅ Created ${allTranslations.length} translation pairs');
  print('✅ Database saved to: $dbPath');
  print('✅ Ready to translate: French→Fula');
}
