import 'package:libsql_dart/libsql_dart.dart';
import 'package:malinali/services/storage_service.dart';
import 'dart:async';

class TursoSyncService {
  static const String _syncUrl = 'TURSO_DATABASE_URL';
  static const String _authToken = 'TURSO_AUTH_TOKEN';

  LibsqlClient? _client;
  bool _isInitialized = false;

  LibsqlClient? get client => _client;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final dbPath = await StorageService.getSyncDatabasePath();
      
      _client = LibsqlClient.replica(
        dbPath,
        syncUrl: _syncUrl,
        authToken: _authToken,
        syncIntervalSeconds: 0, // Disable automatic background sync (frugal)
        readYourWrites: true,
      );

      await _client!.connect();
      _isInitialized = true;
      print('✅ TursoSyncService initialized with libSQL replica');
      
      // Initial sync
      await sync();
    } catch (e) {
      print('❌ Error initializing TursoSyncService: $e');
      // We don't throw here to allow the app to work offline if sync fails
    }
  }

  Future<void> sync() async {
    if (!_isInitialized || _client == null) return;

    try {
      print('🔄 Syncing with Turso...');
      await _client!.sync();
      print('✅ Turso sync completed');
    } catch (e) {
      print('⚠️ Turso sync failed: $e');
    }
  }

  void dispose() {
    _client?.dispose();
    _client = null;
    _isInitialized = false;
  }
}
