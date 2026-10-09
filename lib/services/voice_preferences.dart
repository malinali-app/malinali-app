import 'dart:convert';
import 'dart:io';

import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/services/african_helsinki_models.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/whisper_specialist_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Generic multilingual Whisper size offered at first launch (no brand name).
enum VoiceWhisperSize {
  compact(WhisperModel.tiny, 'environ 75 Mo'),
  quality(WhisperModel.small, 'environ 250 Mo');

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
  });

  final String sourceIso;
  final String targetIso;
  final VoiceWhisperSize whisperSize;
  final String? appLanguageIso;
  final List<String> targetLanguages;

  static const defaults = VoicePreferences(
    sourceIso: 'wo',
    targetIso: 'fr',
    whisperSize: VoiceWhisperSize.quality,
    appLanguageIso: 'fr',
    targetLanguages: ['en', 'fr'],
  );

  Map<String, dynamic> toJson() => {
        'sourceIso': sourceIso,
        'targetIso': targetIso,
        'whisperSize': whisperSize.preferenceKey,
        'appLanguageIso': appLanguageIso,
        'targetLanguages': targetLanguages,
      };

  static VoicePreferences fromJson(Map<String, dynamic> json) {
    final sizeKey = json['whisperSize'] as String? ?? 'quality';
    final size = VoiceWhisperSize.values.firstWhere(
      (s) => s.preferenceKey == sizeKey,
      orElse: () => VoiceWhisperSize.quality,
    );
    return VoicePreferences(
      sourceIso: (json['sourceIso'] as String? ?? 'wo').toLowerCase(),
      targetIso: (json['targetIso'] as String? ?? 'fr').toLowerCase(),
      whisperSize: size,
      appLanguageIso: json['appLanguageIso'] as String?,
      targetLanguages: (json['targetLanguages'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['en', 'fr'],
    );
  }

  VoicePreferences copyWith({
    String? sourceIso,
    String? targetIso,
    VoiceWhisperSize? whisperSize,
    String? appLanguageIso,
    List<String>? targetLanguages,
  }) {
    return VoicePreferences(
      sourceIso: sourceIso ?? this.sourceIso,
      targetIso: targetIso ?? this.targetIso,
      whisperSize: whisperSize ?? this.whisperSize,
      appLanguageIso: appLanguageIso ?? this.appLanguageIso,
      targetLanguages: targetLanguages ?? this.targetLanguages,
    );
  }
}

/// Spoken languages offered on the voice home (downloadable specialist ISOs).
List<WhisperSpecialistPack> voiceSpokenLanguagePacks() {
  final out = <WhisperSpecialistPack>[
    const WhisperSpecialistPack(
      id: 'generic-en',
      labelFr: 'Anglais',
      iso: 'en',
      whisperLang: 'en',
      downloadSizeHint: 'Modèle de base',
      hasMarianOutbound: true,
      upstreamRepo: 'openai/whisper',
      ggmlUrl: 'builtin',
    ),
    const WhisperSpecialistPack(
      id: 'generic-fr',
      labelFr: 'Français (générique)',
      iso: 'fr',
      whisperLang: 'fr',
      downloadSizeHint: 'Modèle de base',
      hasMarianOutbound: true,
      upstreamRepo: 'openai/whisper',
      ggmlUrl: 'builtin',
    ),
  ];
  out.addAll(kWhisperSpecialistPacks.where((p) => p.isDownloadable));
  return out;
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

/// Pinned English → French Marian pack (not in the African catalogue).
final TranslationModel kPinnedEnFrModel = TranslationModel(
  sourceLang: Languages.english,
  targetLang: Languages.french,
  modelId: 'Xenova/opus-mt-en-fr',
  downloadSizeHint: '~75–150 Mo',
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
    if (out.any((m) => m.modelId == model.modelId)) continue;
    out.add(model);
  }
  // Stable order: French first, then alpha by display name.
  out.sort((a, b) {
    final aFr = a.targetLang.localeIntl.locale.languageCode == 'fr';
    final bFr = b.targetLang.localeIntl.locale.languageCode == 'fr';
    if (aFr && !bFr) return -1;
    if (!aFr && bFr) return 1;
    return _languageLabel(a.targetLang).compareTo(_languageLabel(b.targetLang));
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
    if (mSrc == src && mTgt == tgt) return model;
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
