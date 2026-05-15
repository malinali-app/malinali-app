import 'package:libsql_dart/libsql_dart.dart';
import 'package:malinali/services/app_log.dart';
import 'package:malinali/services/database_bootstrap.dart';
import 'package:malinali/services/replica_storage.dart';
import 'package:malinali/services/sync_database_access.dart';

/// Copies translation tables from a libSQL replica into a plain SQLite file.
class DatabaseMaterializer {
  static Future<int> materializeFromLibsql({
    required LibsqlClient client,
    required String appDbPath,
  }) async {
    await ReplicaStorage.deleteReplicaArtifacts(appDbPath);

    final db = SyncDatabaseAccess.openReadWrite(appDbPath);
    try {
      db.execute(DatabaseBootstrap.dictionaryTableSql);
      db.execute(DatabaseBootstrap.phrasesTableSql);
      db.execute(DatabaseBootstrap.dataSourcesTableSql);
      db.execute(DatabaseBootstrap.documentsFtsSql);

      var totalRows = 0;
      final tableRows = await client.query('''
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
      ''');

      for (final table in tableRows) {
        final tableName = table['name']?.toString();
        if (tableName == null ||
            tableName == 'documents' ||
            tableName == 'search_index_meta') {
          continue;
        }

        if (tableName == 'data_sources') {
          AppLog.info('Copie table data_sources...');
          final rows = await client.query('SELECT * FROM data_sources');
          final stmt = db.prepare(
            'INSERT OR REPLACE INTO data_sources (name, author, year, organization, url) '
            'VALUES (?, ?, ?, ?, ?)',
          );
          for (final row in rows) {
            stmt.execute([
              row['name']?.toString() ?? '',
              row['author']?.toString() ?? '',
              row['year']?.toString() ?? '',
              row['organization']?.toString() ?? '',
              row['url']?.toString() ?? '',
            ]);
          }
          stmt.dispose();
          continue;
        }

        final columns = await client.query('PRAGMA table_info($tableName)');
        final columnNames = columns
            .map((column) => column['name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toList();

        final info = SyncDatabaseAccess.describeFromColumnNames(
          tableName,
          columnNames,
        );
        if (info == null) {
          continue;
        }

        final targetTable = info.isPhrasesTable ? 'phrases' : 'dictionary';
        final selectColumns = <String>[
          '${info.sourceColumn} AS source_word',
          '${info.targetColumn} AS translated_word',
        ];
        if (info.categoryColumn != null) {
          selectColumns.add('${info.categoryColumn} AS category');
        }
        final hasProvenanceColumn = columnNames
            .any((name) => name.toLowerCase() == 'source');
        if (hasProvenanceColumn && info.sourceColumn.toLowerCase() != 'source') {
          selectColumns.add('source AS provenance');
        }

        AppLog.info('Copie ${info.tableName} → $targetTable...');
        final rows = await client.query(
          'SELECT ${selectColumns.join(', ')} FROM ${info.tableName}',
        );
        AppLog.info('${rows.length} lignes depuis ${info.tableName}');

        final stmt = db.prepare(
          'INSERT OR REPLACE INTO $targetTable '
          '(source_word, translated_word, category, source) VALUES (?, ?, ?, ?)',
        );
        for (final row in rows) {
          stmt.execute([
            row['source_word']?.toString() ?? '',
            row['translated_word']?.toString() ?? '',
            row['category']?.toString() ?? '',
            row['provenance']?.toString() ?? '',
          ]);
          totalRows++;
        }
        stmt.dispose();
      }

      return totalRows;
    } finally {
      db.dispose();
    }
  }
}
