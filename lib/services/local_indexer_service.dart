import 'dart:io';
import 'package:ml_algo/src/persistence/sqlite_neighbor_search_store.dart';
import 'package:ml_algo/src/retrieval/hybrid_fts_searcher.dart';
import 'package:ml_algo/src/retrieval/translation_pair.dart';
import 'package:malinali/services/embedding_service.dart';
import 'package:malinali/services/storage_service.dart';
import 'package:sqlite3/sqlite3.dart';

class LocalIndexerService {
  final EmbeddingService _embeddingService;
  final String _searcherId = 'fula';
  final String? _overrideSyncDbPath;
  final String? _overrideSearchDbPath;

  LocalIndexerService(this._embeddingService, {String? syncDbPath, String? searchDbPath})
      : _overrideSyncDbPath = syncDbPath,
        _overrideSearchDbPath = searchDbPath;

  /// Indexes new translations from the sync database into the search database.
  Future<void> indexNewTranslations({
    void Function(int current, int total)? onProgress,
  }) async {
    final syncDbPath = _overrideSyncDbPath ?? await StorageService.getSyncDatabasePath();
    final searchDbPath = _overrideSearchDbPath ?? await StorageService.getDatabasePath();

    if (!await File(syncDbPath).exists()) {
      print('ℹ️ Sync database not found, skipping indexing.');
      return;
    }

    final syncDb = sqlite3.open(syncDbPath);
    final searchStore = SQLiteNeighborSearchStore(searchDbPath);

    try {
      // 1. Get all translation IDs from sync database
      final syncRows = syncDb.select('SELECT id, source_text, target_text FROM translations');
      if (syncRows.isEmpty) {
        print('ℹ️ No translations found in sync database.');
        return;
      }

      // 2. Load existing searcher to check what's already indexed
      HybridFTSSearcher? searcher;
      
      try {
        searcher = await HybridFTSSearcher.loadFromStore(searchStore, _searcherId);
        // Note: In a real scenario, we'd check by ID, but HybridFTSSearcher 
        // currently doesn't expose a simple "is this ID indexed" check easily 
        // without custom SQL. For now, we'll use a heuristic or just re-index 
        // if the searcher is missing.
        // To be truly frugal, we'd query the searchStore's internal tables.
      } catch (e) {
        print('ℹ️ Searcher not found, will create new one.');
      }

      // 3. Identify new pairs (Simplified: if searcher exists, we assume it's up to date 
      // for this demo, but in production we'd compare row counts or IDs).
      // Let's implement a simple row count check.
      final searchDbInternal = sqlite3.open(searchDbPath);
      int indexedCount = 0;
      try {
        final tableCheck = searchDbInternal.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='searcher_points'"
        );
        if (tableCheck.isNotEmpty) {
          indexedCount = searchDbInternal.select("SELECT COUNT(*) FROM searcher_points").first[0] as int;
        }
      } finally {
        searchDbInternal.dispose();
      }

      if (indexedCount >= syncRows.length && searcher != null) {
        print('✅ Search index is up to date ($indexedCount rows).');
        return;
      }

      print('🔄 Indexing ${syncRows.length - indexedCount} new translations...');

      // 4. Generate embeddings and build pairs
      final translations = <TranslationPair>[];
      for (var i = 0; i < syncRows.length; i++) {
        final row = syncRows[i];
        final source = row['source_text'] as String;
        final target = row['target_text'] as String;

        // Generate embedding (Local Compute!)
        final embedding = await _embeddingService.generateEmbedding(source);

        translations.add(
          TranslationPair(
            source: source,
            target: target,
            embedding: embedding.toList(),
          ),
        );

        if (onProgress != null) {
          onProgress(i + 1, syncRows.length);
        }
      }

      // 5. Save to search database
      await HybridFTSSearcher.createFromTranslations(
        searchStore,
        translations,
        digitCapacity: 8,
        searcherId: _searcherId,
      );

      print('✅ Successfully indexed ${translations.length} translations.');
    } finally {
      syncDb.dispose();
      searchStore.close();
    }
  }
}
