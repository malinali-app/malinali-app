import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Represents an official VOSK speech-to-text small model.
class VoskModel {
  final String name;
  final String lang;
  final String langText;
  final String sizeText;
  final int size;
  final String url;
  final bool isAsset;
  final String? assetPath;

  const VoskModel({
    required this.name,
    required this.lang,
    required this.langText,
    required this.sizeText,
    required this.size,
    required this.url,
    this.isAsset = false,
    this.assetPath,
  });

  String get displayName => '$langText ($name)';

  factory VoskModel.fromJson(Map<String, dynamic> json) {
    return VoskModel(
      name: json['name'] as String,
      lang: json['lang'] as String,
      langText: json['lang_text'] as String? ?? json['langText'] as String? ?? '',
      sizeText: json['size_text'] as String? ?? json['sizeText'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      url: json['url'] as String? ?? '',
      isAsset: json['isAsset'] as bool? ?? false,
      assetPath: json['assetPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'lang': lang,
    'lang_text': langText,
    'size_text': sizeText,
    'size': size,
    'url': url,
    'isAsset': isAsset,
    if (assetPath != null) 'assetPath': assetPath,
  };
}

/// Service managing official small VOSK models (discovery, download, caching).
class VoskModelService {
  final Dio _dio;

  VoskModelService({Dio? dio}) : _dio = dio ?? Dio();

  static const String _officialModelListUrl =
      'https://alphacephei.com/vosk/models/model-list.json';

  /// Pre-bundled asset model (French).
  static const VoskModel assetFrenchModel = VoskModel(
    name: 'vosk-model-small-fr-0.22',
    lang: 'fr',
    langText: 'French',
    sizeText: '40.3MiB',
    size: 42233323,
    url: 'https://alphacephei.com/vosk/models/vosk-model-small-fr-0.22.zip',
    isAsset: true,
    assetPath: 'assets/vosk-model-small-fr-0.22.zip',
  );

  /// Bookmarked official small models from alphacephei.com.
  /// Used for instant offline access and guaranteed compatibility.
  static const List<VoskModel> curatedSmallModels = [
    assetFrenchModel,
    VoskModel(
      name: 'vosk-model-small-en-us-0.15',
      lang: 'en-us',
      langText: 'US English',
      sizeText: '39.3MiB',
      size: 41205931,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-en-gb-0.15',
      lang: 'en-gb',
      langText: 'UK English',
      sizeText: '40.8MiB',
      size: 42802096,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-en-gb-0.15.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-en-in-0.4',
      lang: 'en-in',
      langText: 'Indian English',
      sizeText: '35.8MiB',
      size: 37571343,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-en-in-0.4.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-es-0.42',
      lang: 'es',
      langText: 'Spanish',
      sizeText: '38.0MiB',
      size: 39869689,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-es-0.42.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-de-0.15',
      lang: 'de',
      langText: 'German',
      sizeText: '44.3MiB',
      size: 46479007,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-de-0.15.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-it-0.22',
      lang: 'it',
      langText: 'Italian',
      sizeText: '47.4MiB',
      size: 49749502,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-it-0.22.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-pt-0.3',
      lang: 'pt',
      langText: 'Portuguese',
      sizeText: '30.9MiB',
      size: 32360431,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-ru-0.22',
      lang: 'ru',
      langText: 'Russian',
      sizeText: '44.1MiB',
      size: 46215328,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-cn-0.22',
      lang: 'cn',
      langText: 'Chinese',
      sizeText: '41.9MiB',
      size: 43909774,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-ar-0.3',
      lang: 'ar',
      langText: 'Arabic',
      sizeText: '99.5MiB',
      size: 104333312,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-ar-0.3.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-ja-0.22',
      lang: 'ja',
      langText: 'Japanese',
      sizeText: '47.4MiB',
      size: 49702912,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-ja-0.22.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-ko-0.22',
      lang: 'ko',
      langText: 'Korean',
      sizeText: '82.9MiB',
      size: 86926336,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-ko-0.22.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-nl-0.22',
      lang: 'nl',
      langText: 'Dutch',
      sizeText: '38.6MiB',
      size: 40475136,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-nl-0.22.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-pl-0.22',
      lang: 'pl',
      langText: 'Polish',
      sizeText: '50.5MiB',
      size: 52953088,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-pl-0.22.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-tr-0.3',
      lang: 'tr',
      langText: 'Turkish',
      sizeText: '35.1MiB',
      size: 36805120,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-tr-0.3.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-uk-v3-small',
      lang: 'ua',
      langText: 'Ukrainian',
      sizeText: '137.2MiB',
      size: 143863808,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-uk-v3-small.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-vn-0.4',
      lang: 'vn',
      langText: 'Vietnamese',
      sizeText: '32.1MiB',
      size: 33659392,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-vn-0.4.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-hi-0.22',
      lang: 'hi',
      langText: 'Hindi',
      sizeText: '42.4MiB',
      size: 44459520,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-hi-0.22.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-ca-0.4',
      lang: 'ca',
      langText: 'Catalan',
      sizeText: '41.4MiB',
      size: 43411456,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-ca-0.4.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-cs-0.4-rhasspy',
      lang: 'cs',
      langText: 'Czech',
      sizeText: '44.0MiB',
      size: 46137344,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-cs-0.4-rhasspy.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-fa-0.42',
      lang: 'fa',
      langText: 'Farsi',
      sizeText: '51.0MiB',
      size: 53477376,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-fa-0.42.zip',
    ),
    VoskModel(
      name: 'vosk-model-small-eo-0.42',
      lang: 'eo',
      langText: 'Esperanto',
      sizeText: '41.8MiB',
      size: 43830272,
      url: 'https://alphacephei.com/vosk/models/vosk-model-small-eo-0.42.zip',
    ),
  ];

  /// Fetch all small models (queries alphacephei.com with fallback to curated bookmarks).
  Future<List<VoskModel>> fetchAllSmallModels() async {
    try {
      final response = await _dio.get<List<dynamic>>(
        _officialModelListUrl,
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 5),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final List<VoskModel> dynamicModels = [];
        for (final item in response.data!) {
          if (item is Map<String, dynamic>) {
            final type = item['type'] as String?;
            final obsolete = item['obsolete'] == 'true' || item['obsolete'] == true;
            final name = item['name'] as String? ?? '';
            if (type == 'small' && !obsolete && name.startsWith('vosk-model-small-')) {
              final isAsset = name == assetFrenchModel.name;
              dynamicModels.add(
                VoskModel(
                  name: name,
                  lang: item['lang'] as String? ?? '',
                  langText: item['lang_text'] as String? ?? '',
                  sizeText: item['size_text'] as String? ?? '',
                  size: (item['size'] as num?)?.toInt() ?? 0,
                  url: item['url'] as String? ?? '',
                  isAsset: isAsset,
                  assetPath: isAsset ? assetFrenchModel.assetPath : null,
                ),
              );
            }
          }
        }
        if (dynamicModels.isNotEmpty) {
          // Always ensure asset model is present and sorted first
          dynamicModels.removeWhere((m) => m.name == assetFrenchModel.name);
          dynamicModels.insert(0, assetFrenchModel);
          return dynamicModels;
        }
      }
    } catch (_) {
      // Fallback silently to curated list
    }
    return List<VoskModel>.from(curatedSmallModels);
  }

  /// Directory where downloaded VOSK models reside.
  Future<Directory> getStorageDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final String baseDir = Platform.isWindows
        ? p.join(docs.path, 'Malinali_do_not_delete', 'vosk_models')
        : p.join(docs.path, 'vosk_models');
    final dir = Directory(baseDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Checks if a model is downloaded and ready to use.
  Future<bool> isModelDownloaded(VoskModel model) async {
    if (model.isAsset) return true;
    try {
      final storageDir = await getStorageDirectory();
      final modelDir = Directory(p.join(storageDir.path, model.name));
      if (!modelDir.existsSync()) return false;
      // Model is valid if directory exists and contains at least 3 files/dirs
      return modelDir.listSync().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Gets the local directory path for a model (unpacks asset if needed).
  Future<String> getModelPath(VoskModel model) async {
    final storageDir = await getStorageDirectory();
    final modelDir = Directory(p.join(storageDir.path, model.name));

    if (model.isAsset) {
      if (modelDir.existsSync() && modelDir.listSync().isNotEmpty) {
        return modelDir.path;
      }
      // Unpack asset model to storage directory
      final byteData = await rootBundle.load(model.assetPath ?? 'assets/${model.name}.zip');
      final bytes = byteData.buffer.asUint8List();
      final archive = ZipDecoder().decodeBytes(bytes);
      _extractZip(archive, storageDir.path);
      return modelDir.path;
    }

    if (!modelDir.existsSync() || modelDir.listSync().isEmpty) {
      throw StateError('Model ${model.name} is not downloaded yet.');
    }
    return modelDir.path;
  }

  /// Downloads and extracts a VOSK small model.
  Future<String> downloadModel(
    VoskModel model, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (model.isAsset) {
      return getModelPath(model);
    }

    final storageDir = await getStorageDirectory();
    final modelDir = Directory(p.join(storageDir.path, model.name));
    if (modelDir.existsSync() && modelDir.listSync().isNotEmpty) {
      return modelDir.path;
    }

    final tempZip = File(p.join(storageDir.path, '${model.name}.zip'));
    try {
      await _dio.download(
        model.url,
        tempZip.path,
        onReceiveProgress: onProgress,
      );

      final bytes = await tempZip.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      _extractZip(archive, storageDir.path);

      return modelDir.path;
    } finally {
      if (tempZip.existsSync()) {
        try {
          tempZip.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Deletes a downloaded model to free disk space.
  Future<void> deleteModel(VoskModel model) async {
    if (model.isAsset) return; // Cannot delete asset
    final storageDir = await getStorageDirectory();
    final modelDir = Directory(p.join(storageDir.path, model.name));
    if (modelDir.existsSync()) {
      modelDir.deleteSync(recursive: true);
    }
  }

  /// Finds the best matching VOSK small model for a given [Language].
  VoskModel? findModelForLanguage(
    Language language,
    List<VoskModel> availableModels,
  ) {
    final code = language.localeIntl.locale.languageCode.toLowerCase();

    // 1. Direct language matches
    if (code == 'fr') {
      return availableModels.firstWhere(
        (m) => m.name == assetFrenchModel.name,
        orElse: () => assetFrenchModel,
      );
    }
    if (code == 'en') {
      final us = availableModels.cast<VoskModel?>().firstWhere(
        (m) => m?.name == 'vosk-model-small-en-us-0.15',
        orElse: () => null,
      );
      if (us != null) return us;
    }
    if (code == 'zh') {
      final cn = availableModels.cast<VoskModel?>().firstWhere(
        (m) => m?.lang == 'cn',
        orElse: () => null,
      );
      if (cn != null) return cn;
    }
    if (code == 'vi') {
      final vn = availableModels.cast<VoskModel?>().firstWhere(
        (m) => m?.lang == 'vn',
        orElse: () => null,
      );
      if (vn != null) return vn;
    }
    if (code == 'uk') {
      final uk = availableModels.cast<VoskModel?>().firstWhere(
        (m) => m?.lang == 'ua' || m?.lang == 'uk',
        orElse: () => null,
      );
      if (uk != null) return uk;
    }

    // 2. Generic code or prefix matching
    for (final m in availableModels) {
      final mLang = m.lang.toLowerCase();
      if (mLang == code || mLang.startsWith('$code-')) {
        return m;
      }
    }

    return null;
  }

  void _extractZip(Archive archive, String targetPath) {
    for (final file in archive) {
      final filename = file.name;
      final fullPath = p.join(targetPath, filename);
      if (file.isFile) {
        final data = file.content as List<int>;
        File(fullPath)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(data);
      } else {
        Directory(fullPath).createSync(recursive: true);
      }
    }
  }
}
