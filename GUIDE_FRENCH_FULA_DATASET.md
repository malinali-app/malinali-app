# Simple Guide: English/French-Fula Translation Dataset

This guide shows you exactly how to combine `EmbeddingService.generateEmbedding()` with SQLite persistence for your English-Fula and French-Fula datasets.

## Complete Example

```dart
import 'package:ml_algo/src/persistence/sqlite_neighbor_search_store.dart';
import 'package:ml_algo/src/retrieval/hybrid_fts_searcher.dart';
import 'package:ml_algo/src/retrieval/translation_pair.dart';
import 'package:malinali/services/embedding_service.dart';
import 'package:path_provider/path_provider.dart';

Future<void> loadFrenchFulaDataset() async {
  // Step 1: Initialize EmbeddingService
  final embeddingService = EmbeddingService();
  await embeddingService.initialize();

  // Step 2: Set up SQLite store
  final appDir = await getApplicationDocumentsDirectory();
  final dbPath = '${appDir.path}/french_fula_translations.db';
  final store = SQLiteNeighborSearchStore(dbPath);

  // Step 3: Load your dataset
  // Replace this with your actual data source (CSV, JSON, etc.)
  final translationPairs = [
    ['Bonjour', 'Jamm nga def'],
    ['Comment allez-vous?', 'Naka nga def?'],
    ['Merci', 'Jërejëf'],
    // ... add all your French-Fula pairs
  ];

  // Step 4: Generate embeddings and create TranslationPair objects
  final translations = <TranslationPair>[];
  
  print('Generating embeddings for ${translationPairs.length} pairs...');
  for (var i = 0; i < translationPairs.length; i++) {
    final pair = translationPairs[i];
    final french = pair[0];
    final fula = pair[1];
    
    // Generate embedding for Fula text (target language)
    // You can also use French if you want to search from Fula to French
    final embeddingVector = await embeddingService.generateEmbedding(fula);
    
    translations.add(TranslationPair(
      french: french,
      english: fula, // Note: "english" field is just the target language
      embedding: embeddingVector.toList(),
    ));
    
    // Progress indicator
    if ((i + 1) % 10 == 0) {
      print('Processed ${i + 1}/${translationPairs.length} pairs...');
    }
  }

  // Step 5: Create searcher and save to database
  final searcher = await HybridFTSSearcher.createFromTranslations(
    store,
    translations,
    digitCapacity: 8,
    searcherId: 'french-fula',
  );

  print('✅ Dataset loaded! ${translations.length} translations ready.');
  
  // Step 6: Save searcher to store (persists to database)
  await searcher.saveToStore();
  
  // Clean up
  embeddingService.dispose();
  store.close();
}
```

## Loading from CSV File

If your dataset is in a CSV file:

```dart
import 'dart:io';
import 'package:csv/csv.dart';

Future<List<List<String>>> loadCsvFile(String filePath) async {
  final file = File(filePath);
  final content = await file.readAsString();
  final rows = const CsvToListConverter().convert(content);
  return rows.map((row) => row.map((cell) => cell.toString()).toList()).toList();
}

Future<void> loadFrenchFulaFromCsv(String csvPath) async {
  // Initialize service
  final embeddingService = EmbeddingService();
  await embeddingService.initialize();

  // Load CSV
  final rows = await loadCsvFile(csvPath);
  // Assuming format: [French, Fula] or [Fula, French]
  
  // Generate embeddings
  final translations = <TranslationPair>[];
  for (var row in rows) {
    final french = row[0];
    final fula = row[1];
    
    final embedding = await embeddingService.generateEmbedding(fula);
    translations.add(TranslationPair(
      french: french,
      english: fula,
      embedding: embedding.toList(),
    ));
  }

  // Create searcher
  final store = SQLiteNeighborSearchStore('path/to/db.db');
  final searcher = await HybridFTSSearcher.createFromTranslations(
    store,
    translations,
    searcherId: 'french-fula',
  );
  
  await searcher.saveToStore();
}
```

## Loading from JSON File

If your dataset is in JSON:

```dart
import 'dart:convert';
import 'dart:io';

Future<void> loadFrenchFulaFromJson(String jsonPath) async {
  final embeddingService = EmbeddingService();
  await embeddingService.initialize();

  // Load JSON
  final file = File(jsonPath);
  final jsonContent = await file.readAsString();
  final data = jsonDecode(jsonContent) as List;
  
  // Generate embeddings
  final translations = <TranslationPair>[];
  for (var item in data) {
    final french = item['french'] as String;
    final fula = item['fula'] as String;
    
    final embedding = await embeddingService.generateEmbedding(fula);
    translations.add(TranslationPair(
      french: french,
      english: fula,
      embedding: embedding.toList(),
    ));
  }

  // Create and save searcher
  final store = SQLiteNeighborSearchStore('path/to/db.db');
  final searcher = await HybridFTSSearcher.createFromTranslations(
    store,
    translations,
    searcherId: 'french-fula',
  );
  
  await searcher.saveToStore();
}
```

## Using the Loaded Dataset

Once loaded, you can search from both English and French:

```dart
Future<void> searchTranslations() async {
  // Load existing searcher
  final appDir = await getApplicationDocumentsDirectory();
  final dbPath = '${appDir.path}/english_french_fula_translations.db';
  final store = SQLiteNeighborSearchStore(dbPath);
  
  final searcher = await HybridFTSSearcher.loadFromStore(
    store,
    searcherId: 'english-french-fula',
  );

  // Initialize embedding service for queries
  final embeddingService = EmbeddingService();
  await embeddingService.initialize();

  // Example 1: Search from English
  final englishQuery = 'In the name of Allah';
  final englishEmbedding = await embeddingService.generateEmbedding(englishQuery);
  
  final englishResults = await searcher.searchHybrid(
    keyword: englishQuery,
    embedding: englishEmbedding,
    k: 5,
  );

  print('English query: "$englishQuery"');
  for (var result in englishResults) {
    print('  ${result.frenchText} -> ${result.englishText}');
  }

  // Example 2: Search from French
  final frenchQuery = 'Au nom d\'Allah';
  final frenchEmbedding = await embeddingService.generateEmbedding(frenchQuery);
  
  final frenchResults = await searcher.searchHybrid(
    keyword: frenchQuery,
    embedding: frenchEmbedding,
    k: 5,
  );

  print('French query: "$frenchQuery"');
  for (var result in frenchResults) {
    print('  ${result.frenchText} -> ${result.englishText}');
  }
}
```

**Note**: Both English and French queries will return Fula translations because:
- We stored embeddings for Fula (target language)
- The multilingual model can match English/French embeddings to Fula embeddings
- FTS search finds matches in both source languages

## Key Points

1. **Initialize EmbeddingService once** - Reuse it for all embeddings
2. **Generate embeddings for target language** - Usually the language you're translating TO
3. **Use `createFromTranslations()`** - Simplest way to create searcher
4. **Call `saveToStore()`** - Persists to database for later use
5. **Progress indicators** - Show progress for large datasets

## Performance Tips

- **Batch processing**: Process 10-50 pairs at a time, show progress
- **Reuse service**: Don't create new `EmbeddingService` for each embedding
- **Save periodically**: For large datasets, save every N pairs
- **Error handling**: Wrap in try-catch, handle individual failures

## Complete Working Example

See `malinali/lib/main.dart` lines 57-127 for the exact pattern used in the app!

