import 'dart:io';
import 'package:path_provider/path_provider.dart';

class StorageService {
  static const String folderName = 'Malinali_DO_NOT_DELETE';

  static Future<String> getStorageDirectoryPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final storageDir = Directory('${appDir.path}/$folderName');
    
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    
    return storageDir.path;
  }

  static Future<String> getDatabasePath() async {
    final storagePath = await getStorageDirectoryPath();
    return '$storagePath/malinali_search.db';
  }

  /// libSQL embedded replica (Turso sync only — do not open with package:sqlite3).
  static Future<String> getSyncDatabasePath() async {
    final storagePath = await getStorageDirectoryPath();
    return '$storagePath/malinali_sync.db';
  }

  /// Plain SQLite database used by search and FTS (package:sqlite3).
  static Future<String> getAppDatabasePath() async {
    final storagePath = await getStorageDirectoryPath();
    return '$storagePath/malinali_app.db';
  }
}
