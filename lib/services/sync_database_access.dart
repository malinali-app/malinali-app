import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Describes a SQLite table that stores French ↔ Pulaar translation rows.
class TranslationTableInfo {
  final String tableName;
  final String sourceColumn;
  final String targetColumn;
  final String? categoryColumn;

  const TranslationTableInfo({
    required this.tableName,
    required this.sourceColumn,
    required this.targetColumn,
    this.categoryColumn,
  });

  bool get isDictionaryTable => tableName.toLowerCase() == 'dictionary';

  bool get isPhrasesTable => tableName.toLowerCase() == 'phrases';
}

class SyncDatabaseAccess {
  static const _ignoredTables = {
    'documents',
    'search_index_meta',
    'sqlite_sequence',
  };

  static Future<void> ensureParentDirectory(String dbPath) async {
    final parent = Directory(File(dbPath).parent.path);
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
  }

  static Database? tryOpenReadOnly(String dbPath) {
    if (!File(dbPath).existsSync()) {
      return null;
    }
    return sqlite3.open(dbPath, mode: OpenMode.readOnly);
  }

  static Database openReadOnly(String dbPath) {
    final db = tryOpenReadOnly(dbPath);
    if (db == null) {
      throw SqliteException(14, 'unable to open database file');
    }
    return db;
  }

  static Database openReadWrite(String dbPath) {
    return sqlite3.open(dbPath, mode: OpenMode.readWriteCreate);
  }

  static List<TranslationTableInfo> discoverTranslationTables(Database db) {
    final tables = db.select('''
      SELECT name FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
    ''');

    final discovered = <TranslationTableInfo>[];
    for (final row in tables) {
      final tableName = row['name'] as String;
      if (_ignoredTables.contains(tableName.toLowerCase())) {
        continue;
      }

      final info = _describeTranslationTable(db, tableName);
      if (info != null) {
        discovered.add(info);
      }
    }

    discovered.sort((a, b) {
      int rank(TranslationTableInfo info) {
        if (info.isDictionaryTable) return 0;
        if (info.isPhrasesTable) return 1;
        return 2;
      }

      final rankCompare = rank(a).compareTo(rank(b));
      if (rankCompare != 0) {
        return rankCompare;
      }
      return a.tableName.compareTo(b.tableName);
    });

    return discovered;
  }

  static TranslationTableInfo? dictionaryTable(Database db) {
    for (final table in discoverTranslationTables(db)) {
      if (table.isDictionaryTable) {
        return table;
      }
    }
    return null;
  }

  static List<TranslationTableInfo> phraseTables(Database db) {
    return discoverTranslationTables(db)
        .where((table) => table.isPhrasesTable)
        .toList();
  }

  static List<TranslationTableInfo> expansionTables(Database db) {
    return discoverTranslationTables(db)
        .where((table) => table.isDictionaryTable || table.isPhrasesTable)
        .toList();
  }

  static int countTranslationRows(Database db) {
    var total = 0;
    for (final table in discoverTranslationTables(db)) {
      total += _countRows(db, table.tableName);
    }
    return total;
  }

  static String describeDatabaseContents(Database db) {
    final tables = discoverTranslationTables(db);
    if (tables.isEmpty) {
      final allTables = db
          .select('''
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
          ''')
          .map((row) => row['name'] as String)
          .toList();
      return 'tables SQLite: ${allTables.isEmpty ? "(aucune)" : allTables.join(", ")}';
    }

    return tables
        .map(
          (table) =>
              '${table.tableName}(${_countRows(db, table.tableName)} lignes)',
        )
        .join(', ');
  }

  static TranslationTableInfo? describeFromColumnNames(
    String tableName,
    Iterable<String> columns,
  ) {
    final columnNames = <String, String>{
      for (final column in columns)
        column.toLowerCase(): column,
    };
    return _infoFromColumnMap(tableName, columnNames);
  }

  static TranslationTableInfo? _describeTranslationTable(
    Database db,
    String tableName,
  ) {
    final columns = db.select('PRAGMA table_info($tableName)');
    return describeFromColumnNames(
      tableName,
      columns.map((column) => column['name'].toString()),
    );
  }

  static TranslationTableInfo? _infoFromColumnMap(
    String tableName,
    Map<String, String> columnNames,
  ) {
    final sourceColumn = columnNames['source_word'] ??
        columnNames['french'] ??
        columnNames['fr'] ??
        columnNames['texte_source'] ??
        columnNames['text_fr'] ??
        columnNames['src'] ??
        _singleColumnMatch(columnNames, 'source');
    final targetColumn = columnNames['translated_word'] ??
        columnNames['pulaar'] ??
        columnNames['fulfulde'] ??
        columnNames['ff'] ??
        columnNames['texte_traduit'] ??
        columnNames['text_ff'] ??
        columnNames['tgt'] ??
        columnNames['target'] ??
        _singleColumnMatch(columnNames, 'translation');
    if (sourceColumn == null || targetColumn == null) {
      return null;
    }
    if (sourceColumn == targetColumn) {
      return null;
    }

    return TranslationTableInfo(
      tableName: tableName,
      sourceColumn: sourceColumn,
      targetColumn: targetColumn,
      categoryColumn: columnNames['category'],
    );
  }

  /// Avoid matching the provenance [source] column when [source_word] exists.
  static String? _singleColumnMatch(
    Map<String, String> columnNames,
    String suffix,
  ) {
    if (columnNames.containsKey('source_word')) {
      return null;
    }
    for (final entry in columnNames.entries) {
      if (entry.key == suffix || entry.key.endsWith('_$suffix')) {
        return entry.value;
      }
    }
    return null;
  }

  static int parseSqlCount(Object? value) {
    if (value == null) {
      return 0;
    }
    if (value is int) {
      return value;
    }
    if (value is BigInt) {
      return value.toInt();
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString()) ?? 0;
  }

  static int _countRows(Database db, String tableName) {
    final row = db.select('SELECT COUNT(*) AS count FROM $tableName').first;
    return parseSqlCount(row['count']);
  }
}
