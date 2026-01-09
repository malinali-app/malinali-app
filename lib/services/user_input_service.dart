import 'package:sqlite3/sqlite3.dart';

/// Service to manage user-inputted translations in SQLite.
/// 
/// User inputs are stored in a separate table and can be searched
/// using full-text search, and easily shared.
class UserInputService {
  final String _dbPath;
  Database? _db;

  UserInputService(this._dbPath) {
    _initializeDatabase();
  }

  void _initializeDatabase() {
    _db = sqlite3.open(_dbPath);
    _createTables();
  }

  void _createTables() {
    final db = _db!;

    // Create translations table (same structure as searcher_points text columns)
    // Add is_user_input flag to label user entries
    db.execute('''
      CREATE TABLE IF NOT EXISTS translations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_text TEXT NOT NULL,
        target_text TEXT NOT NULL,
        source_lang TEXT,
        target_lang TEXT,
        is_user_input INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // Add is_user_input column if table exists without it (migration)
    try {
      db.execute('ALTER TABLE translations ADD COLUMN is_user_input INTEGER NOT NULL DEFAULT 0');
    } catch (e) {
      // Column already exists, ignore
    }

    // Create FTS virtual table for full-text search (same structure as searcher_points_fts)
    try {
      db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS translations_fts USING fts5(
          id UNINDEXED,
          source_text,
          target_text
        )
      ''');
    } catch (e) {
      // Try FTS4 as fallback
      try {
        db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS translations_fts USING fts4(
            id,
            source_text,
            target_text
          )
        ''');
      } catch (e2) {
        // FTS not available, continue without it
        print('Warning: FTS not available for translations. Full-text search will be disabled.');
      }
    }

    // Create indexes for faster lookups
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_translations_created_at
      ON translations(created_at)
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_translations_user_input
      ON translations(is_user_input)
    ''');
  }

  /// Add a user input translation pair.
  /// Returns the ID of the inserted record.
  Future<int> addUserInput({
    required String sourceText,
    required String targetText,
    String? sourceLang,
    String? targetLang,
  }) async {
    final db = _db!;
    
    // Insert into translations table with is_user_input = 1
    final insertStmt = db.prepare('''
      INSERT INTO translations (source_text, target_text, source_lang, target_lang, is_user_input)
      VALUES (?, ?, ?, ?, 1)
    ''');
    
    insertStmt.execute([
      sourceText.trim(),
      targetText.trim(),
      sourceLang,
      targetLang,
    ]);
    
    final id = db.lastInsertRowId;
    insertStmt.dispose();

    // Update FTS index (if available)
    try {
      final ftsStmt = db.prepare('''
        INSERT INTO translations_fts (id, source_text, target_text)
        VALUES (?, ?, ?)
      ''');
      ftsStmt.execute([id, sourceText.trim(), targetText.trim()]);
      ftsStmt.dispose();
    } catch (e) {
      // FTS might not be available, ignore
      print('Warning: Could not update FTS index: $e');
    }

    return id.toInt();
  }

  /// Search user inputs using full-text search.
  /// Returns list of [id, sourceText, targetText] tuples.
  List<Map<String, dynamic>> searchUserInputs(String query) {
    final db = _db!;
    final results = <Map<String, dynamic>>[];

    try {
      // Escape special FTS characters
      var escapedQuery = query.replaceAll("'", "''");
      
      // Try FTS search (only user inputs: is_user_input = 1)
      final ftsStmt = db.prepare('''
        SELECT t.id, t.source_text, t.target_text, t.source_lang, t.target_lang
        FROM translations_fts fts
        JOIN translations t ON t.id = fts.id
        WHERE translations_fts MATCH ? AND t.is_user_input = 1
        ORDER BY rank
        LIMIT 20
      ''');
      
      final rows = ftsStmt.select([escapedQuery]);
      
      for (final row in rows) {
        results.add({
          'id': row[0] as int,
          'sourceText': row[1] as String,
          'targetText': row[2] as String,
          'sourceLang': row[3] as String?,
          'targetLang': row[4] as String?,
        });
      }
      
      ftsStmt.dispose();
    } catch (e) {
      // Fallback to simple LIKE search if FTS fails (only user inputs)
      final likeStmt = db.prepare('''
        SELECT id, source_text, target_text, source_lang, target_lang
        FROM translations
        WHERE is_user_input = 1 AND (source_text LIKE ? OR target_text LIKE ?)
        ORDER BY created_at DESC
        LIMIT 20
      ''');
      
      final searchPattern = '%$query%';
      final rows = likeStmt.select([searchPattern, searchPattern]);
      
      for (final row in rows) {
        results.add({
          'id': row[0] as int,
          'sourceText': row[1] as String,
          'targetText': row[2] as String,
          'sourceLang': row[3] as String?,
          'targetLang': row[4] as String?,
        });
      }
      
      likeStmt.dispose();
    }

    return results;
  }

  /// Get all user inputs.
  List<Map<String, dynamic>> getAllUserInputs() {
    final db = _db!;
    final results = <Map<String, dynamic>>[];

    final stmt = db.prepare('''
      SELECT id, source_text, target_text, source_lang, target_lang, created_at
      FROM translations
      WHERE is_user_input = 1
      ORDER BY created_at DESC
    ''');

    final rows = stmt.select([]);
    for (final row in rows) {
      results.add({
        'id': row[0] as int,
        'sourceText': row[1] as String,
        'targetText': row[2] as String,
        'sourceLang': row[3] as String?,
        'targetLang': row[4] as String?,
        'createdAt': row[5] as String,
      });
    }

    stmt.dispose();
    return results;
  }

  /// Delete a user input by ID.
  Future<bool> deleteUserInput(int id) async {
    final db = _db!;

    // Delete from main table (only if it's a user input)
    final deleteStmt = db.prepare('DELETE FROM translations WHERE id = ? AND is_user_input = 1');
    deleteStmt.execute([id]);
    final changes = db.lastInsertRowId;
    deleteStmt.dispose();

    // Delete from FTS index (if available)
    try {
      final ftsDeleteStmt = db.prepare('DELETE FROM translations_fts WHERE id = ?');
      ftsDeleteStmt.execute([id]);
      ftsDeleteStmt.dispose();
    } catch (e) {
      // Ignore FTS errors
    }

    return changes > 0;
  }

  /// Get count of user inputs.
  int getUserInputCount() {
    final db = _db!;
    final stmt = db.prepare('SELECT COUNT(*) FROM translations WHERE is_user_input = 1');
    final result = stmt.select([]);
    final count = result.first[0] as int;
    stmt.dispose();
    return count;
  }

  /// Export all user inputs as a formatted string for sharing.
  /// Format: grouped by source and target languages
  String exportUserInputs() {
    final inputs = getAllUserInputs();
    if (inputs.isEmpty) {
      return 'No user inputs to share.';
    }

    // Group by source and target languages
    final sourceTexts = <String>[];
    final targetTexts = <String>[];

    for (var i = 0; i < inputs.length; i++) {
      final input = inputs[i];
      sourceTexts.add(input['sourceText'] as String);
      targetTexts.add(input['targetText'] as String);
    }

    final buffer = StringBuffer();
    
    // Source section
    buffer.writeln('source');
    for (final sourceText in sourceTexts) {
      buffer.writeln('- $sourceText');
    }
    buffer.writeln('');

    // Target section
    buffer.writeln('target');
    for (final targetText in targetTexts) {
      buffer.writeln('- $targetText');
    }

    return buffer.toString();
  }

  /// Close the database connection.
  void close() {
    _db?.dispose();
    _db = null;
  }
}
