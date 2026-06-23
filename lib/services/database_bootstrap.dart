import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:malinali/services/search_index_service.dart';
import 'package:malinali/services/sync_database_access.dart';
import 'package:sqlite3/sqlite3.dart';

class DatabaseBootstrap {
  static const String dictionaryTableSql = '''
    CREATE TABLE IF NOT EXISTS dictionary (
        source_word TEXT PRIMARY KEY,
        translated_word TEXT,
        category TEXT,
        source TEXT
    );
  ''';

  static const String phrasesTableSql = '''
    CREATE TABLE IF NOT EXISTS phrases (
        source_word TEXT PRIMARY KEY,
        translated_word TEXT,
        category TEXT,
        source TEXT
    );
  ''';

  static const String dataSourcesTableSql = '''
    CREATE TABLE IF NOT EXISTS data_sources (
        name TEXT PRIMARY KEY,
        author TEXT,
        year TEXT,
        organization TEXT,
        url TEXT
    );
  ''';

  static const String documentsFtsSql = '''
    CREATE VIRTUAL TABLE IF NOT EXISTS documents USING fts5(
        content,
        tokenize = "unicode61 tokenchars '"
    );
  ''';

  static Future<bool> databaseHasTranslationData(String dbPath) async {
    final hasSourceData = await SearchIndexService.databaseHasTranslationData(
      dbPath,
    );
    if (!hasSourceData) {
      return false;
    }

    return SearchIndexService.databaseHasSearchIndex(dbPath);
  }

  static Future<void> createEmptySchema(String dbPath) async {
    final db = SyncDatabaseAccess.openReadWrite(dbPath);
    try {
      db.execute(dictionaryTableSql);
      db.execute(phrasesTableSql);
      db.execute(dataSourcesTableSql);
      db.execute(documentsFtsSql);
    } finally {
      db.dispose();
    }
  }

  static Future<void> ensureDataSources(String dbPath) async {
    final db = SyncDatabaseAccess.openReadWrite(dbPath);
    try {
      db.execute(dataSourcesTableSql);
      final count =
          db.select('SELECT COUNT(*) AS count FROM data_sources').first['count']
              as int;
      if (count == 0) {
        await _seedDataSources(db);
      }
    } finally {
      db.dispose();
    }
  }

  static Future<bool> seedDictionaryFromBundledAssets(
    String dbPath, {
    int? maxRows,
  }) async {
    try {
      final dictionaryTsv = await rootBundle.loadString(
        'assets/fra-ful/dictionary.tsv',
      );

      final db = SyncDatabaseAccess.openReadWrite(dbPath);
      try {
        db.execute(dictionaryTableSql);
        db.execute(phrasesTableSql);
        db.execute(dataSourcesTableSql);
        db.execute(documentsFtsSql);

        await _seedDataSources(db);

        await _seedTranslationTable(
          db,
          table: 'dictionary',
          tsv: dictionaryTsv,
          maxRows: maxRows,
        );

        try {
          final phrasesTsv = await rootBundle.loadString(
            'assets/fra-ful/phrases.tsv',
          );
          await _seedTranslationTable(
            db,
            table: 'phrases',
            tsv: phrasesTsv,
            maxRows: maxRows != null ? (maxRows ~/ 2) : null,
          );
        } on FlutterError {
          // phrases.tsv optional for minimal dev bundles
        }
      } finally {
        db.dispose();
      }

      await SearchIndexService.rebuild(dbPath);
      return true;
    } catch (e) {
      print('⚠️ Could not seed bundled assets: $e');
      return false;
    }
  }

  static Future<void> _seedDataSources(Database db) async {
    try {
      final tsv = await rootBundle.loadString(
        'assets/fra-ful/data_sources.tsv',
      );
      final stmt = db.prepare(
        'INSERT OR REPLACE INTO data_sources (name, author, year, organization, url) '
        'VALUES (?, ?, ?, ?, ?)',
      );
      for (final row in _parseDataSourcesTsv(tsv)) {
        stmt.execute([
          row.name,
          row.author,
          row.year,
          row.organization,
          row.url,
        ]);
      }
      stmt.dispose();
    } on FlutterError {
      // data_sources.tsv optional for minimal dev bundles
    }
  }

  static Future<void> _seedTranslationTable(
    Database db, {
    required String table,
    required String tsv,
    int? maxRows,
  }) async {
    final stmt = db.prepare(
      'INSERT OR REPLACE INTO $table (source_word, translated_word, category, source) VALUES (?, ?, ?, ?)',
    );
    var count = 0;
    for (final row in _parseTranslationTsv(tsv)) {
      stmt.execute([
        row.sourceWord,
        row.translatedWord,
        row.category,
        row.source,
      ]);
      count++;
      if (maxRows != null && count >= maxRows) {
        break;
      }
    }
    stmt.dispose();
  }

  static Future<void> populateDictionaryFromLinePairs(
    String dbPath,
    List<String> sourceLines,
    List<String> targetLines,
  ) async {
    final db = SyncDatabaseAccess.openReadWrite(dbPath);
    try {
      db.execute(dictionaryTableSql);
      db.execute(phrasesTableSql);
      db.execute(documentsFtsSql);

      final stmt = db.prepare(
        'INSERT OR REPLACE INTO dictionary (source_word, translated_word) VALUES (?, ?)',
      );
      for (var i = 0; i < sourceLines.length; i++) {
        stmt.execute([sourceLines[i], targetLines[i]]);
      }
      stmt.dispose();
    } finally {
      db.dispose();
    }

    await SearchIndexService.rebuild(dbPath);
  }

  static List<TranslationTsvRow> _parseTranslationTsv(String content) {
    final rows = <TranslationTsvRow>[];
    final lines = content.split('\n');
    if (lines.isEmpty) {
      return rows;
    }

    for (final rawLine in lines.skip(1)) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final parts = line.split('\t');
      if (parts.length < 2) {
        continue;
      }

      rows.add(
        TranslationTsvRow(
          sourceWord: parts[0],
          translatedWord: parts[1],
          category: parts.length > 2 ? parts[2] : '',
          source: parts.length > 3 ? parts[3] : '',
        ),
      );
    }

    return rows;
  }

  static List<DataSourceTsvRow> _parseDataSourcesTsv(String content) {
    final rows = <DataSourceTsvRow>[];
    final lines = content.split('\n');
    if (lines.isEmpty) {
      return rows;
    }

    for (final rawLine in lines.skip(1)) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final parts = line.split('\t');
      if (parts.isEmpty || parts[0].isEmpty) {
        continue;
      }

      rows.add(
        DataSourceTsvRow(
          name: parts[0],
          author: parts.length > 1 ? parts[1] : '',
          year: parts.length > 2 ? parts[2] : '',
          organization: parts.length > 3 ? parts[3] : '',
          url: parts.length > 4 ? parts[4] : '',
        ),
      );
    }

    return rows;
  }
}

class DataSourceTsvRow {
  final String name;
  final String author;
  final String year;
  final String organization;
  final String url;

  const DataSourceTsvRow({
    required this.name,
    required this.author,
    required this.year,
    required this.organization,
    required this.url,
  });
}

class TranslationTsvRow {
  final String sourceWord;
  final String translatedWord;
  final String category;
  final String source;

  const TranslationTsvRow({
    required this.sourceWord,
    required this.translatedWord,
    required this.category,
    required this.source,
  });
}
