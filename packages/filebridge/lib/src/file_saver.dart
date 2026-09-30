import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// Conditional imports — media_store / document_file_save are mobile-only.
import 'package:media_store_plus/media_store_plus.dart'
    if (dart.library.html) 'package:filebridge/src/file_saver_stub.dart';
import 'package:document_file_save_plus/document_file_save_plus.dart'
    if (dart.library.html) 'package:filebridge/src/file_saver_stub.dart';

class FileSaver {
  static Future<File> makeFileAndWriteAsStringAsync(
    String content,
    String folder,
    String fileName,
  ) async {
    final file = File('$folder/$fileName');
    return file.writeAsString(content);
  }
}

/// Boutique legal names often include `/` and `:`.
/// Those must not become path segments on Android/Windows.
/// `#` is stripped too: Android FileProvider URIs treat it as a fragment.
String sanitizeExportFileName(String fileName) {
  var cleaned = fileName
      .replaceAll(RegExp(r'[<>:"/\\|?*#]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty ||
      cleaned == '.txt' ||
      RegExp(r'^_+$').hasMatch(cleaned)) {
    cleaned = 'export.txt';
  }
  return cleaned;
}

/// macOS save panels sometimes prefix `/Volumes/<disk>`.
@visibleForTesting
String stripMacOsVolumePrefix(String path) {
  final match = RegExp(r'^/Volumes/[^/]+').firstMatch(path);
  if (match == null) return path;
  final stripped = path.substring(match.end);
  return stripped.isEmpty ? path : stripped;
}

abstract class FileSaverV2 {
  static Future<String?> getPathAndAvoidWebError({
    String? testFolderPath,
  }) async {
    if (kIsWeb == false) {
      if (Platform.isAndroid) {
        return (await getApplicationSupportDirectory()).path;
      }
      if (testFolderPath == null || testFolderPath.isEmpty) {
        return (await getApplicationDocumentsDirectory()).path;
      }
    }
    return null;
  }

  /// Soft-fail wrapper around DocumentFileSavePlus.
  static Future<bool> _tryDocumentFileSave(
    Future<void> Function() save,
  ) async {
    try {
      await save();
      return true;
    } on PlatformException catch (e) {
      debugPrint('DocumentFileSavePlus failed: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('DocumentFileSavePlus failed: $e');
      return false;
    }
  }

  /// Save plain text (.txt). [testFolderPath] skips the dialog for tests.
  /// Returns the saved path, or empty if the user cancelled / save failed.
  static Future<String> saveTxt({
    required String content,
    required String fileName,
    String? testFolderPath,
    String l10nText = 'Enregistrement du texte',
  }) async {
    fileName = sanitizeExportFileName(fileName);
    if (!fileName.toLowerCase().endsWith('.txt')) {
      fileName = '$fileName.txt';
    }

    final now = DateTime.now();
    final fileNameTimestamped =
        '${now.hour}h${now.minute}m${now.second}s_$fileName';
    final initialDirectory =
        await getPathAndAvoidWebError(testFolderPath: testFolderPath);

    if (testFolderPath != null && testFolderPath.isNotEmpty) {
      final path =
          testFolderPath + Platform.pathSeparator + fileNameTimestamped;
      await File(path).writeAsString(content);
      return path;
    }

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final outputUri = await FilePicker.saveFile(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        dialogTitle: l10nText,
        fileName: fileNameTimestamped,
        bytes: Uint8List.fromList(utf8.encode(content)),
        initialDirectory: testFolderPath ?? initialDirectory,
      );
      final outputFilePath = outputUri?.toFilePath();
      if (outputFilePath != null && outputFilePath.isNotEmpty) {
        final written = await File(outputFilePath).writeAsString(content);
        return stripMacOsVolumePrefix(written.path);
      }
      return '';
    }

    if (Platform.isAndroid) {
      await MediaStore.ensureInitialized();
      final mediaStorePlugin = MediaStore();
      if ((await mediaStorePlugin.getPlatformSDKInt()) >= 33) {
        MediaStore.appFolder = 'MediaStorePlugin';
        final tempDir = await getTemporaryDirectory();
        final tempPath =
            '${tempDir.path}${Platform.pathSeparator}$fileNameTimestamped';
        await File(tempPath).writeAsString(content);
        final saveInfo = await mediaStorePlugin.saveFile(
          tempFilePath: tempPath,
          dirType: DirType.download,
          dirName: DirType.download.defaults,
        );
        if (saveInfo != null && saveInfo.isSuccessful) {
          return saveInfo.uri.path;
        }
        return '';
      }
      final textBytes = Uint8List.fromList(utf8.encode(content));
      final ok = await _tryDocumentFileSave(
        () => DocumentFileSavePlus().saveFile(
          textBytes,
          fileNameTimestamped,
          'text/plain',
        ),
      );
      return ok ? fileNameTimestamped : '';
    }

    // iOS
    final textBytes = Uint8List.fromList(utf8.encode(content));
    final ok = await _tryDocumentFileSave(
      () => DocumentFileSavePlus().saveFile(
        textBytes,
        fileNameTimestamped,
        'text/plain',
      ),
    );
    return ok ? fileNameTimestamped : '';
  }
}
