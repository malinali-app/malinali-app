import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:languages_dart/languages_dart.dart';

class TranslationModel {
  final Language sourceLang;
  final Language targetLang;
  final String modelId;
  final bool isAsset;

  TranslationModel({
    required this.sourceLang,
    required this.targetLang,
    required this.modelId,
    this.isAsset = false,
  });

  String get _sourceName => sourceLang.name.isEmpty ? sourceLang.nameEn : sourceLang.name;
  String get _targetName => targetLang.name.isEmpty ? targetLang.nameEn : targetLang.name;

  String get displayName => '$_sourceName → $_targetName';
  String get displayEnglishName => '${sourceLang.nameEn} → ${targetLang.nameEn}';
}

class TranslationModelService {
  final Dio _dio = Dio();
  static const String _xenovaAuthor = 'Xenova';

  /// Pre-defined private models (MOAT)
  static final List<TranslationModel> privateModels = [
    TranslationModel(
      sourceLang: Languages.french,
      targetLang: Language(
        Languages.fulah.localeIntl,
        'Pulaar',
        'Pulaar',
      ),
      modelId: 'assets/fr-pul',
      isAsset: true,
    ),
  ];

  /// Fetch all available models that are GUARANTEED to work.
  Future<List<TranslationModel>> fetchAllAvailableModels() async {
    final List<TranslationModel> models = [];
    models.addAll(privateModels);

    try {
      // 1. Fetch all Xenova models (prioritize for compatibility)
      final xenovaResponse = await _dio.get(
        'https://huggingface.co/api/models',
        queryParameters: {
          'author': _xenovaAuthor,
          'search': 'opus-mt-',
          'expand': 'siblings',
        },
      );
      
      final Set<String> safePairs = {};
      if (xenovaResponse.statusCode == 200) {
        for (var m in xenovaResponse.data) {
          final id = m['id'] as String;
          final name = id.split('/').last;
          if (!name.contains('tc-big')) {
            safePairs.add(name);
          }
        }
        _parseAndAddModels(xenovaResponse.data, models);
      }

      // 2. Fetch other models with explicit safetensors tag
      final marianResponse = await _dio.get(
        'https://huggingface.co/api/models',
        queryParameters: {
          'filter': 'marian,safetensors',
          'expand': 'siblings',
          'sort': 'downloads',
          'direction': '-1',
          'limit': 100,
        },
      );

      if (marianResponse.statusCode == 200) {
        _parseAndAddModels(marianResponse.data, models, safeNames: safePairs);
      }
    } catch (e) {
      print('Error fetching models: $e');
    }

    // Sort by display name
    models.sort((a, b) => a.displayName.compareTo(b.displayName));
    return models;
  }

  /// Fetch available target languages for a given source language from confirmed compatible models.
  Future<List<TranslationModel>> fetchAvailableModels(Language sourceLang) async {
    final List<TranslationModel> allModels = await fetchAllAvailableModels();
    final sourceIso = sourceLang.localeIntl.locale.languageCode;

    return allModels.where((m) => 
      m.sourceLang.localeIntl.locale.languageCode == sourceIso
    ).toList();
  }

  @visibleForTesting
  void parseAndAddModelsForTesting(
    List<dynamic> data,
    List<TranslationModel> models, {
    Language? sourceLang,
    Set<String>? safeNames,
  }) =>
      _parseAndAddModels(data, models,
          sourceLang: sourceLang, safeNames: safeNames);

  void _parseAndAddModels(
    List<dynamic> data,
    List<TranslationModel> models, {
    Language? sourceLang,
    Set<String>? safeNames,
  }) {
    for (var model in data) {
      final String id = model['id'] as String? ?? '';
      final namePart = id.split('/').last;
      final lowerName = namePart.toLowerCase();
      final parts = lowerName.split('-');
      final List<dynamic> siblings = model['siblings'] ?? [];
      final bool isXenova = id.startsWith('Xenova/');

      // 1. Strict weight check: must have model.safetensors (Xenova models resolve weights via HF PRs/mirrors)
      final bool hasSafetensors =
          siblings.any((s) => s['rfilename'] == 'model.safetensors');
      if (!hasSafetensors && !isXenova) continue;

      // 2. Strict fast tokenizer check: must have tokenizer.json or confirmed Xenova counterpart
      final bool hasDirectTokenizer = siblings.any(
        (s) =>
            s['rfilename'] == 'tokenizer.json' ||
            s['rfilename'] == 'tokenizer-enc.json',
      );
      final bool hasXenovaFallback =
          safeNames != null && safeNames.contains(lowerName);

      if (!hasDirectTokenizer && !hasXenovaFallback && !isXenova) {
        // Rust Marian Candle strictly requires Hugging Face tokenizer.json.
        // Raw SentencePiece .spm files without tokenizer.json cannot be loaded.
        continue;
      }

      // 3. Filter out oversized or tc-big models (Marian tc-big has 232M params and custom arch)
      final baseModel =
          (model['cardData']?['base_model'] as String?)?.toLowerCase() ?? '';
      final tags = (model['tags'] as List<dynamic>?)
              ?.map((t) => t.toString().toLowerCase())
              .toList() ??
          [];
      if (lowerName.contains('tc-big') ||
          baseModel.contains('tc-big') ||
          tags.any((t) => t.contains('tc-big'))) {
        continue;
      }

      // If safetensors metadata is present, restrict to standard Marian size (<120M params)
      final totalParams = model['safetensors']?['total'] as num?;
      if (totalParams != null && totalParams > 120000000) {
        continue;
      }

      // 4. Language pair parsing
      if (parts.length >= 4 && parts[0] == 'opus' && parts[1] == 'mt') {
        final targetIso = parts.last;
        final srcIso = parts[parts.length - 2];

        final actualSourceLang = sourceLang ?? _getLanguageByIso(srcIso);
        final targetLang = _getLanguageByIso(targetIso);

        if (actualSourceLang != null && targetLang != null) {
          if (!models.any((m) => m.modelId == id)) {
            models.add(
              TranslationModel(
                sourceLang: actualSourceLang,
                targetLang: targetLang,
                modelId: id,
              ),
            );
          }
        }
      } else if (parts.length >= 2) {
        // Fallback for non-opus-mt naming, e.g. "doubleggg/traductor_fr_es"
        final targetIso = parts.last;
        final srcIso = parts[parts.length - 2];

        final actualSourceLang = sourceLang ?? _getLanguageByIso(srcIso);
        final targetLang = _getLanguageByIso(targetIso);

        if (actualSourceLang != null && targetLang != null) {
          if (!models.any((m) => m.modelId == id)) {
            models.add(
              TranslationModel(
                sourceLang: actualSourceLang,
                targetLang: targetLang,
                modelId: id,
              ),
            );
          }
        }
      }
    }
  }

  Language? _getLanguageByIso(String iso) {
    try {
      return Languages.defaultLanguages.firstWhere(
        (l) => l.localeIntl.locale.languageCode.toLowerCase() == iso.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Download model files if not already cached.
  Future<Directory> downloadModel(TranslationModel model) async {
    if (model.isAsset) {
      throw ArgumentError('Cannot download an asset-based model.');
    }

    final docs = await getApplicationDocumentsDirectory();
    final String baseDir = Platform.isWindows ? 'Malinali_do_not_delete/marian_models' : 'marian_models';
    final modelDir = Directory(
      p.join(docs.path, baseDir, model.modelId.replaceAll('/', '_')),
    );

    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    // 1. Core weights and config
    final coreFiles = ['config.json', 'model.safetensors'];
    for (final filename in coreFiles) {
      try {
        await _downloadOneFile(model.modelId, modelDir, filename);
      } on DioException catch (e) {
        if (e.response?.statusCode == 404 && filename == 'model.safetensors') {
          if (model.modelId.startsWith('Xenova/')) {
            final namePart = model.modelId.split('/').last;
            final helsinkiId = 'Helsinki-NLP/$namePart';
            bool downloaded = false;

            // 1. Try Helsinki-NLP main branch
            try {
              await _downloadOneFile(helsinkiId, modelDir, 'model.safetensors');
              downloaded = true;
            } catch (_) {}

            // 2. Try SFconvertbot PR refs (Hugging Face auto-converts to safetensors via PR refs)
            if (!downloaded) {
              for (final pr in ['refs%2Fpr%2F1', 'refs%2Fpr%2F2', 'refs%2Fpr%2F3']) {
                try {
                  await _downloadOneFile(helsinkiId, modelDir, 'model.safetensors', revision: pr);
                  downloaded = true;
                  break;
                } catch (_) {}
              }
            }

            if (!downloaded) {
              throw Exception('Poids "model.safetensors" introuvable pour ce modèle.');
            }
          } else {
            throw Exception('Ce modèle ne contient pas de fichiers "safetensors" compatibles.');
          }
        } else {
          rethrow;
        }
      }
    }

    // 2. Tokenizers
    bool hasCompatibleJson = false;
    
    // We prioritize Xenova's standardized JSON tokenizers
    if (model.modelId.toLowerCase().contains('opus-mt-')) {
      final namePart = model.modelId.split('/').last.toLowerCase();
      final xenovaId = 'Xenova/$namePart';
      for (final filename in ['tokenizer.json', 'tokenizer-enc.json', 'tokenizer-dec.json']) {
        try {
          await _downloadOneFile(xenovaId, modelDir, filename);
          hasCompatibleJson = true;
          break;
        } catch (_) {}
      }
    }

    if (!hasCompatibleJson) {
      for (final filename in ['tokenizer.json', 'tokenizer-enc.json']) {
        try {
          await _downloadOneFile(model.modelId, modelDir, filename);
          hasCompatibleJson = true;
          break; 
        } catch (_) {}
      }
    }

    if (!hasCompatibleJson) {
      throw Exception('Aucun tokenizer compatible trouvé (format JSON requis).');
    }

    return modelDir;
  }

  Future<void> _downloadOneFile(
    String modelId,
    Directory modelDir,
    String filename, {
    String revision = 'main',
  }) async {
    final file = File(p.join(modelDir.path, filename));
    if (await file.exists() && await file.length() > 0) {
      if (filename == 'tokenizer.json') {
        await _cleanTokenizer(file);
      }
      return;
    }

    final url = 'https://huggingface.co/$modelId/resolve/$revision/$filename';
    try {
      await _dio.download(url, file.path);
      if (filename == 'tokenizer.json') {
        await _cleanTokenizer(file);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        rethrow;
      }
      rethrow;
    }
  }

  Future<void> _cleanTokenizer(File file) async {
    try {
      final content = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);

      void cleanData(dynamic obj) {
        if (obj is Map) {
          final keysToRemove = [];
          for (final key in obj.keys) {
            if (obj[key] == null) {
              keysToRemove.add(key);
            } else if (key == 'normalizer' && obj[key] is Map && obj[key]['type'] == 'Precompiled' && obj[key]['precompiled_charsmap'] == null) {
              keysToRemove.add(key);
            } else {
              cleanData(obj[key]);
            }
          }
          for (final key in keysToRemove) {
            obj.remove(key);
          }
        } else if (obj is List) {
          for (final item in obj) {
            cleanData(item);
          }
        }
      }

      cleanData(data);
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      print('Error cleaning tokenizer JSON: $e');
    }
  }
}
