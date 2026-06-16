import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:libsql_dart/libsql_dart.dart';
import 'package:malinali/services/app_log.dart';
import 'package:malinali/services/database_bootstrap.dart';
import 'package:malinali/services/database_materializer.dart';
import 'package:malinali/services/search_index_service.dart';
import 'package:malinali/services/sync_database_access.dart';

class TursoConfigurationException implements Exception {
  final String message;

  const TursoConfigurationException(this.message);

  @override
  String toString() => message;
}

class TursoDownloadResult {
  final RemoteContentsSummary remoteSummary;
  final int materializedRows;

  const TursoDownloadResult({
    required this.remoteSummary,
    required this.materializedRows,
  });
}

class TursoSyncService {
  static const String _unsetUrl = 'TURSO_DATABASE_URL';
  static const String _unsetToken = 'TURSO_AUTH_TOKEN';
  static const Duration _connectTimeout = Duration(seconds: 60);

  static String _syncUrl = const String.fromEnvironment(
    'TURSO_DATABASE_URL',
    defaultValue: _unsetUrl,
  );
  static String _authToken = const String.fromEnvironment(
    'TURSO_AUTH_TOKEN',
    defaultValue: _unsetToken,
  );
  static bool _credentialsResolved = false;

  static bool get isConfigured =>
      _syncUrl.isNotEmpty &&
      _authToken.isNotEmpty &&
      _syncUrl != _unsetUrl &&
      _authToken != _unsetToken;

  static bool skipAutoTursoSync = bool.fromEnvironment(
    'MALINALI_SKIP_AUTO_TURSO_SYNC',
    defaultValue: false,
  );

  static Future<void> ensureCredentialsLoaded({
    bool isDevelopment = false,
  }) async {
    if (isDevelopment) {
      final skipAutoSync = bool.fromEnvironment(
        'MALINALI_SKIP_AUTO_TURSO_SYNC',
        defaultValue: false,
      );
      if (skipAutoSync) {
        skipAutoTursoSync = true;
      }
    }

    if (_credentialsResolved) {
      return;
    }

    AppLog.info('Chargement des identifiants Turso...');

    if (!isConfigured) {
      for (final path in const [
        'secrets.txt',
        r'malinali-app\secrets.txt',
        'malinali-app/secrets.txt',
      ]) {
        await _loadSecretsFromFile(File(path));
        if (isConfigured) {
          AppLog.info('secrets.txt trouvé: $path');
          break;
        }
      }
    }

    if (!isConfigured) {
      await _loadSecretsFromBundle();
      if (isConfigured) {
        AppLog.info('secrets.txt chargé depuis les assets');
      }
    }

    _credentialsResolved = true;

    if (isConfigured) {
      AppLog.info('Turso configuré: ${configuredDatabaseHost ?? _syncUrl}');
    } else {
      AppLog.warn(
        'Turso non configuré. Créez secrets.txt (URL libsql + token) à la racine du projet.',
      );
    }
  }

  static Future<void> _loadSecretsFromFile(File file) async {
    if (!await file.exists()) {
      return;
    }

    _applySecrets(await file.readAsString());
  }

  static Future<void> _loadSecretsFromBundle() async {
    try {
      _applySecrets(await rootBundle.loadString('secrets.txt'));
    } on FlutterError {
      return;
    } catch (_) {
      return;
    }
  }

  static void _applySecrets(String content) {
    final lines =
        content
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('#'))
            .toList();

    if (lines.length < 2) {
      return;
    }

    _syncUrl = _normalizeSyncUrl(lines[0].trim());
    _authToken = lines[1].trim();
  }

  static String _normalizeSyncUrl(String url) {
    if (url.startsWith('libsql://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('http://')) {
      return url.replaceFirst('http://', 'https://');
    }
    return 'libsql://$url';
  }

  static String? get configuredDatabaseHost {
    if (!isConfigured) {
      return null;
    }

    final uri = Uri.tryParse(_syncUrl);
    return uri?.host;
  }

  /// Downloads Turso tables over the network into a plain SQLite [appDbPath].
  Future<TursoDownloadResult> downloadToAppDatabase(
    String appDbPath, {
    void Function(int processed, int total)? onProgress,
  }) async {
    await ensureCredentialsLoaded();

    if (!isConfigured) {
      throw const TursoConfigurationException(
        'Turso n\'est pas configuré. Ajoutez secrets.txt (ligne 1: URL, ligne 2: token).',
      );
    }

    final host = configuredDatabaseHost ?? _syncUrl;
    AppLog.info('Connexion à Turso ($host)...');
    final client = LibsqlClient.remote(_syncUrl, authToken: _authToken);

    try {
      await client.connect().timeout(
        _connectTimeout,
        onTimeout: () {
          throw TursoConfigurationException(
            'Délai dépassé en connexion à Turso ($_connectTimeout). '
            'Vérifiez le réseau et secrets.txt.',
          );
        },
      );
      AppLog.info('Connecté à Turso');

      final remoteSummary = await _describeRemoteContents(client);
      AppLog.info('Turso remote: $remoteSummary');

      if (remoteSummary.totalRows == 0) {
        AppLog.warn('Turso ne contient aucune table de traduction reconnue');
      }

      AppLog.info('Téléchargement vers $appDbPath ...');
      final materializedRows = await DatabaseMaterializer.materializeFromLibsql(
        client: client,
        appDbPath: appDbPath,
        onProgress: onProgress,
      );
      await DatabaseBootstrap.ensureDataSources(appDbPath);

      AppLog.info('Base locale: $materializedRows lignes copiées');

      return TursoDownloadResult(
        remoteSummary: remoteSummary,
        materializedRows: materializedRows,
      );
    } on TursoConfigurationException {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error('Échec connexion/sync Turso', error, stackTrace);
      throw TursoConfigurationException(_describeTursoError(error));
    } finally {
      client.dispose();
    }
  }

  static String _describeTursoError(Object error) {
    final message = error.toString();
    if (message.contains('dns error') ||
        message.contains('lookup address') ||
        message.contains('No address associated with hostname')) {
      final host = configuredDatabaseHost;
      return 'Impossible de joindre Turso (DNS/réseau). '
          'Vérifiez la connexion Internet et l\'URL dans secrets.txt'
          '${host != null ? ' (hôte: $host)' : ''}.';
    }
    if (message.contains('PanicException')) {
      return 'Erreur du client LibSQL lors de la connexion à Turso. '
          'Vérifiez le réseau, l\'URL libsql://…turso.io et le token.';
    }
    return 'Erreur Turso: $message';
  }

  static Future<RemoteContentsSummary> _describeRemoteContents(
    LibsqlClient client,
  ) async {
    final tables = <RemoteTableSummary>[];
    var totalRows = 0;

    final tableRows = await client.query('''
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
    ''');

    AppLog.info('Tables Turso: ${tableRows.map((r) => r['name']).join(', ')}');

    for (final table in tableRows) {
      final tableName = table['name']?.toString();
      if (tableName == null ||
          tableName == 'documents' ||
          tableName == 'search_index_meta') {
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
        tables.add(
          RemoteTableSummary(
            name: tableName,
            rowCount: 0,
            columns: columnNames,
            recognized: false,
          ),
        );
        AppLog.warn('Table $tableName ignorée (colonnes: ${columnNames.join('/')})');
        continue;
      }

      final countRows = await client.query(
        'SELECT COUNT(*) AS count FROM ${info.tableName}',
      );
      final rowCount = countRows.isEmpty
          ? 0
          : SyncDatabaseAccess.parseSqlCount(countRows.first['count']);
      totalRows += rowCount;
      tables.add(
        RemoteTableSummary(
          name: tableName,
          rowCount: rowCount,
          columns: columnNames,
          recognized: true,
        ),
      );
    }

    return RemoteContentsSummary(tables: tables, totalRows: totalRows);
  }
}

class RemoteTableSummary {
  final String name;
  final int rowCount;
  final List<String> columns;
  final bool recognized;

  const RemoteTableSummary({
    required this.name,
    required this.rowCount,
    required this.columns,
    required this.recognized,
  });
}

class RemoteContentsSummary {
  final List<RemoteTableSummary> tables;
  final int totalRows;

  const RemoteContentsSummary({
    required this.tables,
    required this.totalRows,
  });

  @override
  String toString() {
    if (tables.isEmpty) {
      return 'aucune table utilisateur';
    }

    return tables
        .map((table) {
          final status = table.recognized ? 'ok' : 'colonnes non reconnues';
          return '${table.name}(${table.rowCount}, $status: ${table.columns.join('/')})';
        })
        .join('; ');
  }
}
