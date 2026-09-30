// Stub for web when media_store / document_file_save are unavailable.
import 'dart:typed_data';

class MediaStore {
  static String appFolder = '';

  static Future<void> ensureInitialized() async {}

  Future<int> getPlatformSDKInt() async => 0;

  Future<SaveInfo?> saveFile({
    required String tempFilePath,
    required DirType dirType,
    required DirType dirName,
  }) async =>
      null;
}

class SaveInfo {
  final bool isSuccessful;
  final Uri uri;
  SaveInfo({required this.isSuccessful, required this.uri});
}

class DirType {
  static final photo = DirType._('photo');
  static final download = DirType._('download');
  DirType._(this.name);
  final String name;
  DirType get defaults => this;
}

class DocumentFileSavePlus {
  Future<void> saveFile(
    Uint8List data,
    String fileName,
    String mimeType,
  ) async {}

  Future<void> saveMultipleFiles({
    required List<Uint8List> dataList,
    required List<String> fileNameList,
    required List<String> mimeTypeList,
  }) async {}
}
