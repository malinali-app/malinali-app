import 'dart:io';

/// Removes a libSQL embedded-replica database and its sidecar files.
class ReplicaStorage {
  static Future<void> deleteReplicaArtifacts(String dbPath) async {
    final dbFile = File(dbPath);
    final directory = dbFile.parent;
    if (!await directory.exists()) {
      return;
    }

    final baseName = dbFile.uri.pathSegments.last;
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }

      final fileName = entity.uri.pathSegments.last;
      final isReplicaArtifact =
          fileName == baseName ||
          fileName.startsWith('$baseName-') ||
          fileName.startsWith('$baseName.');

      if (isReplicaArtifact) {
        await entity.delete();
      }
    }

  }
}
