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

  static Future<String> getSyncDatabasePath() async {
    final storagePath = await getStorageDirectoryPath();
    return '$storagePath/malinali_sync.db';
  }
}
