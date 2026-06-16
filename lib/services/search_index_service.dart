import 'package:flutter/foundation.dart';
import 'package:malinali/services/database_bootstrap.dart';
import 'package:malinali/services/sync_database_access.dart';
import 'package:sqlite3/sqlite3.dart';

class SearchIndexService {
  static const String metaTableSql = '''
    CREATE TABLE IF NOT EXISTS search_index_meta (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      dictionary_count INTEGER NOT NULL,
      dictionary_checksum INTEGER NOT NULL,
      phrases_count INTEGER NOT NULL DEFAULT 0,
      phrases_checksum INTEGER NOT NULL DEFAULT 0,
      indexed_at TEXT NOT NULL
    );
  ''';

  static Future<bool> databaseHasSearchIndex(String dbPath) async {
    final db = SyncDatabaseAccess.openReadOnly(dbPath);
    try {
      final documentCount = db.select('SELECT COUNT(*) AS count FROM documents');
      return documentCount.isNotEmpty && documentCount.first['count'] as int > 0;
    } on SqliteException {
      return false;
    } finally {
      db.dispose();
    }
  }

  static Future<bool> databaseHasDictionaryData(String dbPath) async {
    return databaseHasTranslationData(dbPath);
  }

  static Future<bool> databaseHasTranslationData(String dbPath) async {
    return (await countTranslationRowsOnDisk(dbPath)) > 0;
  }

  static Future<int> countTranslationRowsOnDisk(String dbPath) async {
    final db = SyncDatabaseAccess.openReadOnly(dbPath);
    try {
      return SyncDatabaseAccess.countTranslationRows(db);
    } on SqliteException {
      return 0;
    } finally {
      db.dispose();
    }
  }

  static Future<void> checkpointReplica(String dbPath) async {
    final db = SyncDatabaseAccess.openReadWrite(dbPath);
    try {
      db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } on SqliteException {
      return;
    } finally {
      db.dispose();
    }
  }

  static Future<String> describeTranslationData(String dbPath) async {
    final db = SyncDatabaseAccess.openReadOnly(dbPath);
    try {
      return SyncDatabaseAccess.describeDatabaseContents(db);
    } on SqliteException catch (error) {
      return 'lecture SQLite impossible: $error';
    } finally {
      db.dispose();
    }
  }

  static Future<bool> isIndexStale(String dbPath) async {
    final db = SyncDatabaseAccess.openReadOnly(dbPath);
    try {
      _ensureMetaSchema(db);
      final dictionary = _readTableFingerprint(db, 'dictionary');
      final phrases = _readTableFingerprint(db, 'phrases');
      final combined = _readCombinedFingerprint(db);
      if (combined.count == 0) {
        return false;
      }

      final meta = db.select(
        'SELECT dictionary_count, dictionary_checksum, phrases_count, phrases_checksum '
        'FROM search_index_meta WHERE id = 1',
      );
      if (meta.isEmpty) {
        return true;
      }

      final documentCount = db.select('SELECT COUNT(*) AS count FROM documents');
      if (documentCount.isEmpty || documentCount.first['count'] as int == 0) {
        return true;
      }

      final row = meta.first;
      final storedCombinedCount =
          (row['dictionary_count'] as int) + (row['phrases_count'] as int);
      final storedCombinedChecksum =
          (row['dictionary_checksum'] as int) + (row['phrases_checksum'] as int);

      if (dictionary.count > 0 || phrases.count > 0) {
        return row['dictionary_count'] != dictionary.count ||
            row['dictionary_checksum'] != dictionary.checksum ||
            row['phrases_count'] != phrases.count ||
            row['phrases_checksum'] != phrases.checksum;
      }

      return storedCombinedCount != combined.count ||
          storedCombinedChecksum != combined.checksum;
    } on SqliteException {
      return true;
    } finally {
      db.dispose();
    }
  }

  static Future<void> rebuildIfNeeded(
    String dbPath, {
    bool force = false,
  }) async {
    if (!force && !await isIndexStale(dbPath)) {
      return;
    }

    await compute(rebuild, dbPath);
  }

  static Future<void> rebuild(String dbPath) async {
    final db = SyncDatabaseAccess.openReadWrite(dbPath);
    try {
      db.execute(DatabaseBootstrap.dictionaryTableSql);
      db.execute(DatabaseBootstrap.phrasesTableSql);
      db.execute(DatabaseBootstrap.dataSourcesTableSql);
      db.execute(DatabaseBootstrap.documentsFtsSql);
      _ensureMetaSchema(db);

      var dictionary = _readTableFingerprint(db, 'dictionary');
      var phrases = _readTableFingerprint(db, 'phrases');
      final translationTables = SyncDatabaseAccess.discoverTranslationTables(db);
      db.execute('DELETE FROM documents');

      if (translationTables.isEmpty) {
        db.execute('DELETE FROM search_index_meta WHERE id = 1');
        return;
      }

      if (dictionary.count == 0 && phrases.count == 0) {
        final combined = _readCombinedFingerprint(db);
        dictionary = combined;
        phrases = (count: 0, checksum: 0);
      }

      final stmt = db.prepare('INSERT INTO documents (content) VALUES (?)');
      db.execute('BEGIN TRANSACTION');
      try {
        for (final table in translationTables) {
          final rows = db.select(
            'SELECT ${table.sourceColumn} AS source_word, '
            '${table.targetColumn} AS translated_word '
            'FROM ${table.tableName} '
            'ORDER BY ${table.sourceColumn}',
          );
          for (final row in rows) {
            stmt.execute([
              '${row['source_word']} → ${row['translated_word']}',
            ]);
          }
        }
        db.execute('COMMIT');
      } catch (e) {
        db.execute('ROLLBACK');
        rethrow;
      }
      stmt.dispose();

      db.execute('DELETE FROM search_index_meta WHERE id = 1');
      final metaStmt = db.prepare(
        'INSERT INTO search_index_meta '
        '(id, dictionary_count, dictionary_checksum, phrases_count, phrases_checksum, indexed_at) '
        'VALUES (1, ?, ?, ?, ?, ?)',
      );
      metaStmt.execute([
        dictionary.count,
        dictionary.checksum,
        phrases.count,
        phrases.checksum,
        DateTime.now().toUtc().toIso8601String(),
      ]);
      metaStmt.dispose();
    } finally {
      db.dispose();
    }
  }

  static void _ensureMetaSchema(Database db) {
    db.execute(metaTableSql);

    final columns = db
        .select('PRAGMA table_info(search_index_meta)')
        .map((row) => row['name'] as String)
        .toSet();

    if (!columns.contains('phrases_count')) {
      db.execute(
        'ALTER TABLE search_index_meta ADD COLUMN phrases_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!columns.contains('phrases_checksum')) {
      db.execute(
        'ALTER TABLE search_index_meta ADD COLUMN phrases_checksum INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  static bool _tableExists(Database db, String table) {
    final rows = db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  static ({int count, int checksum}) _readTableFingerprint(
    Database db,
    String table,
  ) {
    if (!_tableExists(db, table)) {
      return (count: 0, checksum: 0);
    }

    final row = db.select('''
      SELECT COUNT(*) AS count,
             COALESCE(SUM(LENGTH(source_word) + LENGTH(translated_word)), 0) AS checksum
      FROM $table
    ''').first;

    return (
      count: row['count'] as int,
      checksum: row['checksum'] as int,
    );
  }

  static ({int count, int checksum}) _readCombinedFingerprint(Database db) {
    var count = 0;
    var checksum = 0;

    for (final table in SyncDatabaseAccess.discoverTranslationTables(db)) {
      final row = db.select('''
        SELECT COUNT(*) AS count,
               COALESCE(SUM(LENGTH(${table.sourceColumn}) + LENGTH(${table.targetColumn})), 0) AS checksum
        FROM ${table.tableName}
      ''').first;
      count += row['count'] as int;
      checksum += row['checksum'] as int;
    }

    return (count: count, checksum: checksum);
  }
}
