import 'dart:convert';
import 'dart:io';

import 'package:malinali/services/translation_model_service.dart';
import 'package:marian_flutter/marian_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Process-lifetime cache for the loaded Marian translator.
///
/// Survives Activity recreation while the Android process is alive. Cleared
/// automatically on process death (cold start must reload from disk).
class MarianRuntime {
  MarianRuntime._();
  static final MarianRuntime instance = MarianRuntime._();

  MarianService? _marian;
  TranslationModel? _model;

  MarianService? get marian => _marian;
  TranslationModel? get model => _model;

  bool get isReady => _marian != null && _model != null;

  void attach(MarianService marian, TranslationModel model) {
    _marian = marian;
    _model = model;
  }

  void clear() {
    _marian = null;
    _model = null;
  }

  static Future<File> _lastModelFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final base =
        Platform.isWindows ? 'Malinali_do_not_delete' : 'marian_models';
    final dir = Directory(p.join(docs.path, base));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, 'last_selected_model.json'));
  }

  /// Persist the user's last translation model for the next cold start.
  static Future<void> saveLastSelectedModel(TranslationModel model) async {
    final file = await _lastModelFile();
    await file.writeAsString(jsonEncode(model.toPreferenceJson()));
  }

  /// Load the last selected model, or null if missing / unreadable.
  static Future<TranslationModel?> loadLastSelectedModel() async {
    try {
      final file = await _lastModelFile();
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      return TranslationModel.fromPreferenceJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Prefer last saved model when already on disk; otherwise [defaultBootModel].
  static Future<TranslationModel> resolveBootModel(
    TranslationModelService modelService,
  ) async {
    final last = await loadLastSelectedModel();
    if (last != null) {
      if (last.isAsset || await modelService.isModelDownloaded(last)) {
        return last;
      }
      // Match known catalog entries (private / boot) by id if JSON was sparse.
      for (final known in [
        TranslationModelService.defaultBootModel,
        ...TranslationModelService.privateModels,
      ]) {
        if (known.modelId == last.modelId &&
            (known.isAsset || await modelService.isModelDownloaded(known))) {
          return known;
        }
      }
    }
    return TranslationModelService.defaultBootModel;
  }
}
