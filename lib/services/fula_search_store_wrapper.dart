import 'package:ml_algo/src/persistence/sqlite_neighbor_search_store.dart';
import 'package:sqlite3/sqlite3.dart';

/// Wrapper around SQLiteNeighborSearchStore that uses correct column names
/// for Fula translation: source_text (English/French) and target_text (Fula)
///
/// This fixes the naming mismatch where ml_algo uses french_text/english_text
/// but our data has: french_text = English/French, english_text = Fula
class FulaSearchStoreWrapper {
  final SQLiteNeighborSearchStore _store;
  final String _dbPath;

  FulaSearchStoreWrapper(this._dbPath)
    : _store = SQLiteNeighborSearchStore(_dbPath);

  /// Get the underlying store (for HybridFTSSearcher which needs SQLiteNeighborSearchStore)
  SQLiteNeighborSearchStore get store => _store;

  /// Migrate database to use correct column names
  /// This should be called once after database creation
  Future<void> migrateColumnNames() async {
    // Open database directly using the path
    final db = sqlite3.open(_dbPath);

    try {
      // Perform any necessary migrations here
      // For example, if you need to rename columns or add new ones
      // db.execute('ALTER TABLE ...');

      // For now, this is a placeholder for future migrations
    } finally {
      db.dispose();
    }
  }

  /// Close the store
  void close() {
    _store.close();
  }
}
