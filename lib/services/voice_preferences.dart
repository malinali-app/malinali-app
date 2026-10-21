import 'dart:convert';
import 'dart:io';

import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/services/african_helsinki_models.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/whisper_specialist_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
/// Generic multilingual Whisper size offered at first launch (no brand name).
enum VoiceWhisperSize {
  compact(WhisperModel.tiny, 'environ 103 Mo'),
  quality(WhisperModel.small, 'environ 375 Mo');

  const VoiceWhisperSize(this.model, this.sizeHintFr);

  final WhisperModel model;
  final String sizeHintFr;

  String get preferenceKey => name;
}

/// Persisted voice-chat pair and generic speech size.
class VoicePreferences {
  const VoicePreferences({
    required this.sourceIso,
    required this.targetIso,
    required this.whisperSize,
    this.appLanguageIso,
    this.targetLanguages = const ['en', 'fr'],
    this.useFastSttForEnFr = false,
  });

  final String sourceIso;
  final String targetIso;
  final VoiceWhisperSize whisperSize;
  final String? appLanguageIso;
  final List<String> targetLanguages;
  final bool useFastSttForEnFr;

  /// Voice sources we stand behind: FR/EN speech → Wolof (and other high-BLEU
  /// targets), plus Fon speech → French (pragmatic ST specialist).
  static const defaults = VoicePreferences(
    sourceIso: 'fr',
    targetIso: 'wo',
    whisperSize: VoiceWhisperSize.quality,
    appLanguageIso: 'fr',
    targetLanguages: ['en', 'fr'],
    useFastSttForEnFr: true,
  );

  /// Spoken-language ISOs offered in voice setup / pair pickers.
  static const allowedVoiceSourceIsos = {'en', 'fr', 'fon'};

  Map<String, dynamic> toJson() => {
        'sourceIso': sourceIso,
        'targetIso': targetIso,
        'whisperSize': whisperSize.preferenceKey,
        'appLanguageIso': appLanguageIso,
        'targetLanguages': targetLanguages,
        'useFastSttForEnFr': useFastSttForEnFr,
      };

  static VoicePreferences fromJson(Map<String, dynamic> json) {
    final sizeKey = json['whisperSize'] as String? ?? 'quality';
    final size = VoiceWhisperSize.values.firstWhere(
      (s) => s.preferenceKey == sizeKey,
      orElse: () => VoiceWhisperSize.quality,
    );
    var sourceIso = (json['sourceIso'] as String? ?? defaults.sourceIso)
        .toLowerCase();
    var targetIso = (json['targetIso'] as String? ?? defaults.targetIso)
        .toLowerCase();
    // Migrate retired low-resource voice sources (e.g. wo→fr → fr→wo).
    if (!allowedVoiceSourceIsos.contains(sourceIso)) {
      if (sourceIso == 'wo' && (targetIso == 'en' || targetIso == 'fr')) {
        sourceIso = targetIso;
        targetIso = 'wo';
      } else {
        sourceIso = defaults.sourceIso;
        targetIso = defaults.targetIso;
      }
    }
    return VoicePreferences(
      sourceIso: sourceIso,
      targetIso: targetIso,
      whisperSize: size,
      appLanguageIso: json['appLanguageIso'] as String?,
      targetLanguages: (json['targetLanguages'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['en', 'fr'],
      useFastSttForEnFr: json['useFastSttForEnFr'] as bool? ?? true,
    );
  }

  VoicePreferences copyWith({
    String? sourceIso,
    String? targetIso,
    VoiceWhisperSize? whisperSize,
    String? appLanguageIso,
    List<String>? targetLanguages,
    bool? useFastSttForEnFr,
  }) {
    return VoicePreferences(
      sourceIso: sourceIso ?? this.sourceIso,
      targetIso: targetIso ?? this.targetIso,
      whisperSize: whisperSize ?? this.whisperSize,
      appLanguageIso: appLanguageIso ?? this.appLanguageIso,
      targetLanguages: targetLanguages ?? this.targetLanguages,
      useFastSttForEnFr: useFastSttForEnFr ?? this.useFastSttForEnFr,
    );
  }
}

/// Spoken languages offered on the voice home.
///
/// FR/EN use the generic multilingual Whisper. Fon uses the Fo→FR specialist.
List<WhisperSpecialistPack> voiceSpokenLanguagePacks() {
  final fon = whisperSpecialistById('fon-small');
  return [
    const WhisperSpecialistPack(
      id: 'generic-en',
      labelFr: 'Anglais',
      iso: 'en',
      whisperLang: 'en',
      downloadSizeHint: 'Modèle de base',
      hasMarianOutbound: true,
      upstreamRepo: 'openai/whisper',
      builtin: true,
    ),
    const WhisperSpecialistPack(
      id: 'generic-fr',
      labelFr: 'Français (générique)',
      iso: 'fr',
      whisperLang: 'fr',
      downloadSizeHint: 'Modèle de base',
      hasMarianOutbound: true,
      upstreamRepo: 'openai/whisper',
      builtin: true,
    ),
    if (fon != null && fon.isDownloadable) fon,
  ];
}

/// Display language for a voice source ISO.
Language? voiceLanguageByIso(String iso) {
  final code = iso.toLowerCase();
  final fromSpecialist = languageForWhisperIso(code);
  if (fromSpecialist != null) return fromSpecialist;
  try {
    return Languages.defaultLanguages.firstWhere(
      (l) => l.localeIntl.locale.languageCode.toLowerCase() == code,
    );
  } catch (_) {
    return africanLanguageByIso(code);
  }
}

/// Voice hops: ONNX twin of a Candle / Xenova pack when we have one.
TranslationModel voiceOnnxHop(TranslationModel model) {
  const twins = <String, String>{
    'Xenova/opus-mt-en-fr': 'malinali-app/opus-mt-en-fr-onnx',
    'Helsinki-NLP/opus-mt-en-fr': 'malinali-app/opus-mt-en-fr-onnx',
    // Standard Helsinki FR→EN. The tiny pack is too weak for voice,
    // especially the French → English → Wolof cascade.
    'Xenova/opus-mt-fr-en': 'malinali-app/opus-mt-fr-en-onnx',
    'Helsinki-NLP/opus-mt-fr-en': 'malinali-app/opus-mt-fr-en-onnx',
    'Helsinki-NLP/opus-mt_tiny_fra-eng': 'malinali-app/opus-mt-fr-en-onnx',
    'malinali-app/opus-mt_tiny_fra-eng-onnx': 'malinali-app/opus-mt-fr-en-onnx',
    'malinali-app/traduction-wolof-en':
        'malinali-app/traduction-wolof-en-onnx',
    'malinali-app/traduction-en-wolof':
        'malinali-app/traduction-en-wolof-onnx',
  };
  final onnxId = twins[model.modelId];
  if (onnxId == null) return model;
  return TranslationModel(
    sourceLang: model.sourceLang,
    targetLang: model.targetLang,
    modelId: onnxId,
    downloadSizeHint: onnxId.contains('tiny') ? '~35 Mo' : '~140 Mo',
    qualityHint: model.qualityHint,
    sourcePrefix: model.sourcePrefix,
  );
}

/// Pinned English → French Marian pack (not in the African catalogue).
final TranslationModel kPinnedEnFrModel = voiceOnnxHop(
  TranslationModel(
    sourceLang: Languages.english,
    targetLang: Languages.french,
    modelId: 'Xenova/opus-mt-en-fr',
    downloadSizeHint: '~75–150 Mo',
  ),
);

/// Pinned French → English hop for the Wolof cascade (and FR→EN voice).
final TranslationModel kPinnedFrEnModel = voiceOnnxHop(
  TranslationModel(
    sourceLang: Languages.french,
    targetLang: Languages.english,
    modelId: 'Xenova/opus-mt-fr-en',
    downloadSizeHint: '~75–150 Mo',
  ),
);

/// Raw English target (no further Marian translation after speech → English).
final TranslationModel kRawEnglishModel = TranslationModel(
  sourceLang: Languages.english,
  targetLang: Languages.english,
  modelId: 'raw-english',
  downloadSizeHint: '0 Mo',
  qualityHint: 'English',
);

/// English → X targets for the voice picker (African en→* + French + fine-tunes).
List<TranslationModel> voiceEnglishTargetModels() {
  final out = <TranslationModel>[kPinnedEnFrModel, kRawEnglishModel];
  for (final pair in kAfricanHelsinkiOpusPairs) {
    if (pair.sourceIso != 'en') continue;
    final target = voiceLanguageByIso(pair.targetIso);
    if (target == null) continue;
    out.add(
      TranslationModel(
        sourceLang: Languages.english,
        targetLang: target,
        modelId: pair.modelId,
        downloadSizeHint: '~290 Mo',
        qualityHint: formatOpusBleuHint(pair.qualityHint),
      ),
    );
  }
  for (final model in TranslationModelService.candleFineTunes) {
    if (model.sourceLang.localeIntl.locale.languageCode.toLowerCase() != 'en') {
      continue;
    }
    final hop = voiceOnnxHop(model);
    if (out.any((m) => m.modelId == hop.modelId)) continue;
    out.add(hop);
  }
  out.sort((a, b) {
    return _languageLabel(a.targetLang).toLowerCase().compareTo(
          _languageLabel(b.targetLang).toLowerCase(),
        );
  });
  return out;
}

String _languageLabel(Language language) =>
    language.name.isEmpty ? language.nameEn : language.name;

/// Curated Marian model for [sourceIso] → [targetIso], if listed.
TranslationModel? curatedMarianForPair({
  required String sourceIso,
  required String targetIso,
}) {
  final src = sourceIso.toLowerCase();
  final tgt = targetIso.toLowerCase();
  if (src == 'en' && tgt == 'fr') return kPinnedEnFrModel;
  if (src == 'fr' && tgt == 'en') return kPinnedFrEnModel;
  for (final pair in kAfricanHelsinkiOpusPairs) {
    if (pair.sourceIso == src && pair.targetIso == tgt) {
      final source = voiceLanguageByIso(pair.sourceIso);
      final target = voiceLanguageByIso(pair.targetIso);
      if (source == null || target == null) return null;
      return TranslationModel(
        sourceLang: source,
        targetLang: target,
        modelId: pair.modelId,
        downloadSizeHint: '~290 Mo',
        qualityHint: formatOpusBleuHint(pair.qualityHint),
      );
    }
  }
  for (final model in TranslationModelService.candleFineTunes) {
    final mSrc = model.sourceLang.localeIntl.locale.languageCode.toLowerCase();
    final mTgt = model.targetLang.localeIntl.locale.languageCode.toLowerCase();
    if (mSrc == src && mTgt == tgt) {
      // Direct FR→WO is BLEU 9.3; voice/auto routing uses FR→EN→WO instead.
      if (model.modelId == 'malinali-app/traduction-fr-wolof') continue;
      return voiceOnnxHop(model);
    }
  }
  return null;
}

class VoicePreferencesStore {
  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    final base = Platform.isWindows
        ? p.join(docs.path, 'Malinali_do_not_delete')
        : docs.path;
    final dir = Directory(base);
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, 'voice_preferences.json'));
  }

  Future<VoicePreferences?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      return VoicePreferences.fromJson(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(VoicePreferences prefs) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(prefs.toJson()));
  }

  Future<bool> hasCompletedSetup() async {
    return (await load()) != null;
  }
}
