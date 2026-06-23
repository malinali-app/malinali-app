import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:malinali/services/database_bootstrap.dart';

void main() {
  test('Database schema initialization (FTS5) should succeed', () {
    // We use an in-memory database for testing
    final db = sqlite3.openInMemory();
    
    try {
      // Test each table creation individually to pinpoint failures
      db.execute(DatabaseBootstrap.dictionaryTableSql);
      db.execute(DatabaseBootstrap.phrasesTableSql);
      db.execute(DatabaseBootstrap.dataSourcesTableSql);
      
      // This is the one that was failing
      db.execute(DatabaseBootstrap.documentsFtsSql);
      
      // Verify the table exists
      final result = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='documents'"
      );
      expect(result.length, 1, reason: 'The documents FTS table should be created');
      
      // Verify we can insert and search (to ensure tokenizer is valid)
      db.execute("INSERT INTO documents (content) VALUES ('L''arbre est vert')");
      final searchResult = db.select(
        "SELECT content FROM documents WHERE documents MATCH 'arbre'"
      );
      expect(searchResult.length, 1);
      expect(searchResult.first['content'], "L'arbre est vert");
      
    } finally {
      db.dispose();
    }
  });
}
