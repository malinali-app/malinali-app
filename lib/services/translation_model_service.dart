import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/generated/hf_token.g.dart';

class TranslationModel {
  final Language sourceLang;
  final Language targetLang;
  final String modelId;
  final bool isAsset;
  /// Private HF repos need a Bearer token (see [hfReadToken] or [authToken]).
  final bool requiresAuth;
  /// Optional per-model HF token (Bring Your Own private repos).
  final String? authToken;
  /// User-added via Advanced / BYO settings.
  final bool isCustom;
  /// Approximate download size shown in the settings confirm dialog.
  final String? downloadSizeHint;

  TranslationModel({
    required this.sourceLang,
    required this.targetLang,
    required this.modelId,
    this.isAsset = false,
    this.requiresAuth = false,
    this.authToken,
    this.isCustom = false,
    this.downloadSizeHint,
  });

  String get _sourceName => sourceLang.name.isEmpty ? sourceLang.nameEn : sourceLang.name;
  String get _targetName => targetLang.name.isEmpty ? targetLang.nameEn : targetLang.name;

  String get displayName => '$_sourceName → $_targetName';
  String get displayEnglishName => '${sourceLang.nameEn} → ${targetLang.nameEn}';

  String get pairKey {
    final s = sourceLang.localeIntl.locale.languageCode.toLowerCase();
    final t = targetLang.localeIntl.locale.languageCode.toLowerCase();
    return '$s|$t';
  }

  Map<String, dynamic> toJson() => {
        'modelId': modelId,
        'sourceIso': sourceLang.localeIntl.locale.languageCode,
        'targetIso': targetLang.localeIntl.locale.languageCode,
        'sourceName': _sourceName,
        'targetName': _targetName,
        'requiresAuth': requiresAuth || (authToken != null && authToken!.isNotEmpty),
        'authToken': authToken,
        'isCustom': true,
        'downloadSizeHint': downloadSizeHint,
      };

  /// Full snapshot for last-selected-model persistence (boot / resume).
  Map<String, dynamic> toPreferenceJson() => {
        'modelId': modelId,
        'sourceIso': sourceLang.localeIntl.locale.languageCode,
        'targetIso': targetLang.localeIntl.locale.languageCode,
        'sourceName': _sourceName,
        'targetName': _targetName,
        'requiresAuth': requiresAuth || (authToken != null && authToken!.isNotEmpty),
        'authToken': authToken,
        'isCustom': isCustom,
        'isAsset': isAsset,
        'downloadSizeHint': downloadSizeHint,
      };

  static TranslationModel? fromJson(Map<String, dynamic> json) {
    return _fromJsonMap(json, forceCustom: true);
  }

  static TranslationModel? fromPreferenceJson(Map<String, dynamic> json) {
    return _fromJsonMap(json, forceCustom: false);
  }

  static TranslationModel? _fromJsonMap(
    Map<String, dynamic> json, {
    required bool forceCustom,
  }) {
    final modelId = json['modelId'] as String?;
    if (modelId == null || modelId.isEmpty) return null;
    final sourceIso = (json['sourceIso'] as String? ?? '').toLowerCase();
    final targetIso = (json['targetIso'] as String? ?? '').toLowerCase();
    Language? source;
    Language? target;
    try {
      source = Languages.defaultLanguages.firstWhere(
        (l) => l.localeIntl.locale.languageCode.toLowerCase() == sourceIso,
      );
    } catch (_) {
      source = null;
    }
    try {
      target = Languages.defaultLanguages.firstWhere(
        (l) => l.localeIntl.locale.languageCode.toLowerCase() == targetIso,
      );
    } catch (_) {
      target = null;
    }
    // Fulah / Pulaar often missing as a catalog entry.
    if (target == null &&
        (targetIso == 'ff' ||
            targetIso == 'fuv' ||
            (json['targetName'] as String?)?.toLowerCase().contains('pulaar') ==
                true)) {
      target = Language(
        Languages.fulah.localeIntl,
        (json['targetName'] as String?) ?? 'Pulaar',
        'Pulaar',
      );
    }
    if (source == null || target == null) return null;
    final token = json['authToken'] as String?;
    return TranslationModel(
      sourceLang: source,
      targetLang: target,
      modelId: modelId,
      isAsset: json['isAsset'] == true,
      requiresAuth: json['requiresAuth'] == true ||
          (token != null && token.isNotEmpty),
      authToken: token,
      isCustom: forceCustom || json['isCustom'] == true,
      downloadSizeHint: json['downloadSizeHint'] as String?,
    );
  }
}

class TranslationModelService {
  final Dio _dio = Dio();
  static const String _xenovaAuthor = 'Xenova';

  /// Boot default: small public Xenova FR→EN (single tokenizer.json).
  static final TranslationModel defaultBootModel = TranslationModel(
    sourceLang: Languages.french,
    targetLang: Languages.english,
    modelId: 'Xenova/opus-mt-fr-en',
  );

  /// Pre-defined private models (MOAT) — downloaded on demand from HF.
  static final List<TranslationModel> privateModels = [
    TranslationModel(
      sourceLang: Languages.french,
      targetLang: Language(
        Languages.fulah.localeIntl,
        'Pulaar',
        'Pulaar',
      ),
      modelId: 'flutter-painter/french-fula',
      requiresAuth: true,
      downloadSizeHint: '~285 Mo',
    ),
  ];

  /// Fetch all available models that are GUARANTEED to work.
  Future<List<TranslationModel>> fetchAllAvailableModels() async {
    final List<TranslationModel> models = [];
    models.addAll(privateModels);
    models.addAll(await loadCustomModels());

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

    // One model per language pair (avoids duplicate "English" targets).
    final deduped = dedupeByLanguagePair(models);
    deduped.sort((a, b) => a.displayName.compareTo(b.displayName));
    return deduped;
  }

  /// Keep a single model per source→target ISO pair.
  /// Exception: BYO (custom) models are NOT deduped, allowing multiple models per pair.
  /// If a custom model exists for a pair, it hides the non-custom ones for that pair.
  @visibleForTesting
  List<TranslationModel> dedupeByLanguagePair(List<TranslationModel> models) {
    final best = <String, TranslationModel>{};
    final List<TranslationModel> custom = [];
    final Set<String> customPairs = {};
    
    // Collect all custom models
    for (final model in models) {
      if (model.isCustom) {
        custom.add(model);
        customPairs.add(model.pairKey);
      }
    }
    
    // Dedupe non-custom models, skipping those already covered by custom models
    for (final model in models) {
      if (model.isCustom) continue;
      
      final key = model.pairKey;
      if (customPairs.contains(key)) continue;
      
      final current = best[key];
      if (current == null || _modelRank(model) < _modelRank(current)) {
        best[key] = model;
      }
    }
    
    return [...best.values, ...custom];
  }

  int _modelRank(TranslationModel model) {
    if (model.isCustom || model.modelId == 'flutter-painter/french-fula') {
      return 0;
    }
    if (model.modelId == defaultBootModel.modelId) return 1;
    if (model.modelId.startsWith('Xenova/')) return 2;
    if (model.requiresAuth) return 3;
    return 4;
  }

  /// Preferred model for a source→target ISO pair from [models].
  TranslationModel? preferredModelForPair(
    List<TranslationModel> models, {
    required String sourceIso,
    required String targetIso,
  }) {
    final s = sourceIso.toLowerCase();
    final t = targetIso.toLowerCase();
    final matches = models
        .where(
          (m) =>
              m.sourceLang.localeIntl.locale.languageCode.toLowerCase() == s &&
              m.targetLang.localeIntl.locale.languageCode.toLowerCase() == t,
        )
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => _modelRank(a).compareTo(_modelRank(b)));
    return matches.first;
  }

  Future<File> _customModelsFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final base = Platform.isWindows
        ? 'Malinali_do_not_delete'
        : 'marian_models';
    final dir = Directory(p.join(docs.path, base));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, 'custom_hf_models.json'));
  }

  Future<List<TranslationModel>> loadCustomModels() async {
    try {
      final file = await _customModelsFile();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      final out = <TranslationModel>[];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          final model = TranslationModel.fromJson(item);
          if (model != null) out.add(model);
        } else if (item is Map) {
          final model = TranslationModel.fromJson(
            item.map((k, v) => MapEntry(k.toString(), v)),
          );
          if (model != null) out.add(model);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCustomModels(List<TranslationModel> models) async {
    final file = await _customModelsFile();
    final payload = models.where((m) => m.isCustom).map((m) => m.toJson()).toList();
    await file.writeAsString(jsonEncode(payload));
  }

  /// Probe a Hugging Face Marian / Candle repo and register it as a custom model.
  Future<TranslationModel> registerHuggingFaceModel({
    required String repoId,
    String? authToken,
    Language? sourceLang,
    Language? targetLang,
  }) async {
    final id = repoId.trim().replaceFirst(RegExp(r'^https?://huggingface\.co/'), '');
    if (!id.contains('/') || id.split('/').length != 2) {
      throw ArgumentError(
        'Identifiant invalide. Attendu: org/nom (ex. Xenova/opus-mt-fr-en).',
      );
    }

    final headers = <String, dynamic>{};
    final token = authToken?.trim();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await _dio.get(
      'https://huggingface.co/api/models/$id',
      options: Options(headers: headers.isEmpty ? null : headers),
    );
    if (response.statusCode != 200) {
      throw Exception('Dépôt introuvable ou accès refusé ($id).');
    }

    final data = response.data as Map<String, dynamic>;
    final siblings = (data['siblings'] as List?)
            ?.map((s) => (s as Map)['rfilename'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];

    final hasConfig = siblings.contains('config.json');
    final hasWeights = siblings.contains('model.safetensors');
    final hasTokJson = siblings.contains('tokenizer.json');
    final hasTokEnc = siblings.contains('tokenizer-enc.json');
    final hasTokDec = siblings.contains('tokenizer-dec.json');
    if (!hasConfig || !hasWeights) {
      throw Exception(
        'Le dépôt doit contenir config.json et model.safetensors '
        '(format Candle / Marian safetensors).',
      );
    }
    if (!hasTokJson && !(hasTokEnc && hasTokDec)) {
      throw Exception(
        'Tokenizer manquant: tokenizer.json '
        'ou la paire tokenizer-enc.json + tokenizer-dec.json.',
      );
    }

    Language? src = sourceLang;
    Language? tgt = targetLang;
    final namePart = id.split('/').last.toLowerCase();
    final parts = namePart.split('-');
    if ((src == null || tgt == null) &&
        parts.length >= 4 &&
        parts[0] == 'opus' &&
        parts[1] == 'mt') {
      src ??= _getLanguageByIso(parts[parts.length - 2]);
      tgt ??= _getLanguageByIso(parts.last);
    }
    if (src == null || tgt == null) {
      throw Exception(
        'Impossible de déduire les langues depuis le nom du dépôt. '
        'Choisissez source et cible manuellement.',
      );
    }

    final model = TranslationModel(
      sourceLang: src,
      targetLang: tgt,
      modelId: id,
      requiresAuth: token != null && token.isNotEmpty,
      authToken: token,
      isCustom: true,
      downloadSizeHint: hasTokEnc ? '~285 Mo' : '~75–150 Mo',
    );

    final custom = await loadCustomModels();
    custom.removeWhere((m) => m.modelId == id);
    custom.add(model);
    await saveCustomModels(custom);
    return model;
  }

  Future<void> removeCustomModel(String modelId) async {
    final custom = await loadCustomModels();
    custom.removeWhere((m) => m.modelId == modelId);
    await saveCustomModels(custom);
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

  Future<Directory> modelDirectory(TranslationModel model) async {
    final docs = await getApplicationDocumentsDirectory();
    final String baseDir =
        Platform.isWindows ? 'Malinali_do_not_delete/marian_models' : 'marian_models';
    return Directory(
      p.join(docs.path, baseDir, model.modelId.replaceAll('/', '_')),
    );
  }

  Future<bool> isModelDownloaded(TranslationModel model) async {
    if (model.isAsset) return true;
    try {
      final modelDir = await modelDirectory(model);
      if (!await modelDir.exists()) return false;
      
      final mainFile = File(p.join(modelDir.path, 'model.safetensors'));
      if (!await mainFile.exists() || await mainFile.length() == 0) return false;
      
      final configFile = File(p.join(modelDir.path, 'config.json'));
      if (!await configFile.exists() || await configFile.length() == 0) return false;

      // Check for at least one tokenizer file
      final tokenizer = File(p.join(modelDir.path, 'tokenizer.json'));
      final tokenizerEnc = File(p.join(modelDir.path, 'tokenizer-enc.json'));
      
      final hasTokenizer = (await tokenizer.exists() && await tokenizer.length() > 0) ||
                           (await tokenizerEnc.exists() && await tokenizerEnc.length() > 0);
      
      return hasTokenizer;
    } catch (_) {
      return false;
    }
  }

  /// Download model files if not already cached.
  Future<Directory> downloadModel(TranslationModel model) async {
    if (model.isAsset) {
      throw ArgumentError('Cannot download an asset-based model.');
    }

    final modelDir = await modelDirectory(model);

    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    // 1. Core weights and config
    final coreFiles = ['config.json', 'model.safetensors'];
    for (final filename in coreFiles) {
      try {
        await _downloadOneFile(
          model.modelId,
          modelDir,
          filename,
          requiresAuth: model.requiresAuth,
          authToken: model.authToken,
        );
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
              throw Exception('Le modèle n\'a pas pu être téléchargé (poids introuvables).');
            }
          } else {
            throw Exception('Le modèle n\'a pas pu être téléchargé (fichiers incompatibles).');
          }
        } else {
          rethrow;
        }
      }
    }

    // 2. Tokenizers — Xenova opus-mt: single tokenizer.json
    final isOpusMt = model.modelId.toLowerCase().contains('opus-mt-');
    if (isOpusMt && !model.requiresAuth) {
      final namePart = model.modelId.split('/').last.toLowerCase();
      final xenovaId = 'Xenova/$namePart';
      for (final filename in ['tokenizer.json', 'tokenizer-enc.json', 'tokenizer-dec.json']) {
        try {
          await _downloadOneFile(xenovaId, modelDir, filename);
          return modelDir;
        } catch (_) {}
      }
      for (final filename in ['tokenizer.json', 'tokenizer-enc.json']) {
        try {
          await _downloadOneFile(model.modelId, modelDir, filename);
          return modelDir;
        } catch (_) {}
      }
    }

    // Dual-tokenizer Candle pack (e.g. flutter-painter/french-fula): need BOTH enc and dec.
    final dualMissing = <String>[];
    for (final filename in ['tokenizer-enc.json', 'tokenizer-dec.json']) {
      try {
        await _downloadOneFile(
          model.modelId,
          modelDir,
          filename,
          requiresAuth: model.requiresAuth,
          authToken: model.authToken,
        );
      } catch (_) {
        dualMissing.add(filename);
      }
    }
    if (dualMissing.isEmpty) {
      return modelDir;
    }

    try {
      await _downloadOneFile(
        model.modelId,
        modelDir,
        'tokenizer.json',
        requiresAuth: model.requiresAuth,
        authToken: model.authToken,
      );
      return modelDir;
    } catch (_) {}

    throw Exception(
      'Aucun tokenizer compatible trouvé (format JSON requis). '
      'Manquant: ${dualMissing.join(', ')}',
    );
  }

  Future<void> _downloadOneFile(
    String modelId,
    Directory modelDir,
    String filename, {
    String revision = 'main',
    bool requiresAuth = false,
    String? authToken,
  }) async {
    final file = File(p.join(modelDir.path, filename));
    if (await file.exists() && await file.length() > 0) {
      if (filename == 'tokenizer.json') {
        await _cleanTokenizer(file);
      }
      return;
    }

    final url = 'https://huggingface.co/$modelId/resolve/$revision/$filename';
    String? bearer;
    if (authToken != null && authToken.trim().isNotEmpty) {
      bearer = authToken.trim();
    } else if (requiresAuth) {
      bearer = hfReadToken();
    }
    final options = Options(
      headers: bearer != null ? {'Authorization': 'Bearer $bearer'} : null,
    );
    try {
      await _dio.download(url, file.path, options: options);
      if (filename == 'tokenizer.json') {
        await _cleanTokenizer(file);
      }
    } catch (e) {
      // If the download was interrupted, delete the partial file
      // to avoid thinking it's fully downloaded next time.
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
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
