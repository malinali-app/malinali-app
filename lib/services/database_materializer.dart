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
    int batchSize = 500,
    void Function(int processed, int total)? onProgress,
  }) async {
    await ReplicaStorage.deleteReplicaArtifacts(appDbPath);

    final db = SyncDatabaseAccess.openReadWrite(appDbPath);
    try {
      db.execute(DatabaseBootstrap.dictionaryTableSql);
      db.execute(DatabaseBootstrap.phrasesTableSql);
      db.execute(DatabaseBootstrap.dataSourcesTableSql);
      db.execute(DatabaseBootstrap.documentsFtsSql);

      var totalRowsProcessed = 0;
      final tableRows = await client.query('''
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
      ''');

      // 1. Calculer le nombre total de lignes à copier pour le progrès
      var grandTotal = 0;
      final tablesToCopy = <String>[];
      for (final table in tableRows) {
        final tableName = table['name']?.toString();
        if (tableName == null ||
            tableName == 'documents' ||
            tableName == 'search_index_meta') {
          continue;
        }
        tablesToCopy.add(tableName);
        final countRes = await client.query('SELECT COUNT(*) as count FROM $tableName');
        grandTotal += (countRes.first['count'] as num).toInt();
      }

      AppLog.info('Total de lignes à synchroniser: $grandTotal');

      for (final tableName in tablesToCopy) {
        if (tableName == 'data_sources') {
          AppLog.info('Copie table data_sources (pagination)...');
          final countRes = await client.query('SELECT COUNT(*) as count FROM data_sources');
          final tableTotal = (countRes.first['count'] as num).toInt();
          var tableProcessed = 0;

          final stmt = db.prepare(
            'INSERT OR REPLACE INTO data_sources (name, author, year, organization, url) '
            'VALUES (?, ?, ?, ?, ?)',
          );

          while (tableProcessed < tableTotal) {
            final rows = await client.query(
              'SELECT * FROM data_sources LIMIT $batchSize OFFSET $tableProcessed',
            );
            if (rows.isEmpty) break;

            db.execute('BEGIN TRANSACTION');
            try {
              for (final row in rows) {
                stmt.execute([
                  row['name']?.toString() ?? '',
                  row['author']?.toString() ?? '',
                  row['year']?.toString() ?? '',
                  row['organization']?.toString() ?? '',
                  row['url']?.toString() ?? '',
                ]);
                tableProcessed++;
                totalRowsProcessed++;
              }
              db.execute('COMMIT');
            } catch (e) {
              db.execute('ROLLBACK');
              rethrow;
            }
            onProgress?.call(totalRowsProcessed, grandTotal);
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

        AppLog.info('Copie ${info.tableName} → $targetTable (pagination)...');
        final countRes = await client.query('SELECT COUNT(*) as count FROM ${info.tableName}');
        final tableTotal = (countRes.first['count'] as num).toInt();
        var tableProcessed = 0;

        final stmt = db.prepare(
          'INSERT OR REPLACE INTO $targetTable '
          '(source_word, translated_word, category, source) VALUES (?, ?, ?, ?)',
        );

        while (tableProcessed < tableTotal) {
          final rows = await client.query(
            'SELECT ${selectColumns.join(', ')} FROM ${info.tableName} '
            'LIMIT $batchSize OFFSET $tableProcessed',
          );
          if (rows.isEmpty) break;

          db.execute('BEGIN TRANSACTION');
          try {
            for (final row in rows) {
              stmt.execute([
                row['source_word']?.toString() ?? '',
                row['translated_word']?.toString() ?? '',
                row['category']?.toString() ?? '',
                row['provenance']?.toString() ?? '',
              ]);
              tableProcessed++;
              totalRowsProcessed++;
            }
            db.execute('COMMIT');
          } catch (e) {
            db.execute('ROLLBACK');
            rethrow;
          }
          onProgress?.call(totalRowsProcessed, grandTotal);
        }
        stmt.dispose();
      }

      return totalRowsProcessed;
    } finally {
      db.dispose();
    }
  }
}
