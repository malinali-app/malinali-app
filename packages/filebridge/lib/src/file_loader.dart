import 'dart:io' show File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const csvTypeGroup =
    XTypeGroup(label: 'csv', extensions: ['csv', 'tsv', 'txt']);

const textTypeGroup =
    XTypeGroup(label: 'text', extensions: ['txt', 'text', 'md']);

const audioTypeGroup = XTypeGroup(
  label: 'audio',
  extensions: ['opus', 'ogg', 'wav', 'm4a', 'mp3', 'aac', 'amr'],
);

/// Cross-platform file picking helpers (ported from weebi filebridge).
abstract class FileLoaderMonolith {
  /// Pick a plain-text document (.txt / .md / .text).
  static Future<File> loadTextFileFromUserPick({
    String titlel10n = 'Choix du document',
  }) async {
    if (kIsWeb) {
      return File('');
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final initialDirectory =
          (await getApplicationDocumentsDirectory()).path;
      try {
        final result = await openFile(
          initialDirectory: initialDirectory,
          acceptedTypeGroups: [textTypeGroup, csvTypeGroup],
        );
        return File(result?.path ?? '');
      } on PlatformException catch (e) {
        debugPrint('$e');
        return File('');
      }
    }
    try {
      final PlatformFile? result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['txt', 'text', 'md', 'csv', 'tsv'],
        dialogTitle: titlel10n,
      );
      return File(result?.path ?? '');
    } on PlatformException catch (e) {
      debugPrint('$e');
      return File('');
    }
  }

  /// Pick an audio file (WhatsApp .opus / .ogg, wav, m4a, …).
  static Future<File> loadAudioFileFromUserPick({
    String titlel10n = 'Choix du fichier audio',
  }) async {
    if (kIsWeb) {
      return File('');
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final initialDirectory =
          (await getApplicationDocumentsDirectory()).path;
      try {
        final result = await openFile(
          initialDirectory: initialDirectory,
          acceptedTypeGroups: [audioTypeGroup],
        );
        return File(result?.path ?? '');
      } on PlatformException catch (e) {
        debugPrint('$e');
        return File('');
      }
    }
    try {
      final PlatformFile? result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['opus', 'ogg', 'wav', 'm4a', 'mp3', 'aac', 'amr'],
        dialogTitle: titlel10n,
      );
      return File(result?.path ?? '');
    } on PlatformException catch (e) {
      debugPrint('$e');
      return File('');
    }
  }

  static Future<File> loadCsvFileFromUserPick() async {
    if (kIsWeb) {
      return File('');
    }
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final initialDirectory =
          (await getApplicationDocumentsDirectory()).path;
      try {
        final result = await openFile(
          initialDirectory: initialDirectory,
          acceptedTypeGroups: [csvTypeGroup],
        );
        return File(result?.path ?? '');
      } on PlatformException catch (e) {
        debugPrint('$e');
        return File('');
      }
    }
    try {
      final PlatformFile? result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv', 'tsv', 'txt'],
      );
      return File(result?.path ?? '');
    } on PlatformException catch (e) {
      debugPrint('$e');
      return File('');
    }
  }

  /// Read UTF-8 text from [filePath]. Returns empty string on failure.
  static Future<String> readTextFile(String filePath) async {
    if (filePath.isEmpty) return '';
    try {
      return await File(filePath).readAsString();
    } catch (e) {
      debugPrint('readTextFile failed: $e');
      return '';
    }
  }
}
