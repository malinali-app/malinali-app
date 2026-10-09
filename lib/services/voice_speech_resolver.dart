import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/whisper_specialist_models.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// How speech reaches English for a voice turn.
enum VoiceSpeechStrategy {
  /// Fine-tune trained to emit English, then Marian English→target.
  englishOutputFineTune,

  /// Fine-tune transcribes source language, Marian source→English, then English→target.
  transcribeThenMarianToEnglish,

  /// Source language direct to target language (no English bridge).
  directTranslate,

  /// Generic multilingual Whisper with translate-to-English, then Marian English→target.
  genericTranslate,
}

/// Resolved models for one voice turn.
class VoiceSpeechPlan {
  const VoiceSpeechPlan({
    required this.strategy,
    required this.whisperSize,
    required this.whisperLanguage,
    this.specialist,
    this.sourceToEnglish,
    this.englishToTarget,
  });

  final VoiceSpeechStrategy strategy;
  final VoiceWhisperSize whisperSize;

  /// whisper.cpp language token. Never `auto` for a language Whisper knows.
  /// Wolof has no `<|wo|>` token; the fine-tune is prompted with English.
  final String whisperLanguage;

  final WhisperSpecialistPack? specialist;
  final TranslationModel? sourceToEnglish;
  final TranslationModel? englishToTarget;

  WhisperModel get genericModel => whisperSize.model;

  bool get usesSpecialist => specialist != null;

  bool get needsGenericWhisper =>
      strategy == VoiceSpeechStrategy.genericTranslate ||
      (strategy == VoiceSpeechStrategy.englishOutputFineTune &&
          specialist == null);

  bool get translateToEnglish =>
      strategy == VoiceSpeechStrategy.genericTranslate ||
      (specialist?.emitsEnglish ?? false);

  List<TranslationModel> get marianDownloads {
    final out = <TranslationModel>[];
    if (sourceToEnglish != null) out.add(sourceToEnglish!);
    if (englishToTarget != null) out.add(englishToTarget!);
    return out;
  }
}

/// Picks the best speech→English chain for [prefs].
///
/// Same ISO on both sides of a hop. Close languages are never aliased.
class VoiceSpeechResolver {
  const VoiceSpeechResolver();

  VoiceSpeechPlan resolve(VoicePreferences prefs) {
    final sourceIso = prefs.sourceIso.toLowerCase();
    final targetIso = prefs.targetIso.toLowerCase();

    // No downloadable fine-tune: generic Whisper emits English, then Marian
    // English→target. There is no source transcript to feed a wo→* model.
    if (sourceIso == 'wo' && _downloadablePackForIso(sourceIso) == null) {
      final englishToTarget = targetIso == 'en'
          ? null
          : curatedMarianForPair(sourceIso: 'en', targetIso: targetIso);
      return VoiceSpeechPlan(
        strategy: VoiceSpeechStrategy.genericTranslate,
        whisperSize: prefs.whisperSize,
        whisperLanguage: 'en',
        englishToTarget: englishToTarget,
      );
    }

    // 1. Try a direct Marian model for source -> target
    final directModel = curatedMarianForPair(sourceIso: sourceIso, targetIso: targetIso);
    if (directModel != null) {
      // We still need a Whisper pack to transcribe the source
      final pack = _downloadablePackForIso(sourceIso);
      return VoiceSpeechPlan(
        strategy: VoiceSpeechStrategy.directTranslate,
        whisperSize: prefs.whisperSize,
        whisperLanguage: _whisperLanguage(sourceIso, pack),
        specialist: pack,
        sourceToEnglish: directModel, // Using this field for source -> target
        englishToTarget: null,
      );
    }

    // 2. Fall back to bridge through English
    final englishToTarget = targetIso == 'en'
        ? null
        : curatedMarianForPair(sourceIso: 'en', targetIso: targetIso);

    final pack = _downloadablePackForIso(sourceIso);

    if (pack != null && pack.emitsEnglish) {
      return VoiceSpeechPlan(
        strategy: VoiceSpeechStrategy.englishOutputFineTune,
        whisperSize: prefs.whisperSize,
        whisperLanguage: _whisperLanguage(sourceIso, pack),
        specialist: pack,
        englishToTarget: englishToTarget,
      );
    }

    if (pack != null && pack.isDownloadable) {
      final sourceToEnglish = curatedMarianForPair(
        sourceIso: sourceIso,
        targetIso: 'en',
      );
      if (sourceToEnglish != null) {
        return VoiceSpeechPlan(
          strategy: VoiceSpeechStrategy.transcribeThenMarianToEnglish,
          whisperSize: prefs.whisperSize,
          whisperLanguage: _whisperLanguage(sourceIso, pack),
          specialist: pack,
          sourceToEnglish: sourceToEnglish,
          englishToTarget: englishToTarget,
        );
      }
    }

    return VoiceSpeechPlan(
      strategy: VoiceSpeechStrategy.genericTranslate,
      whisperSize: prefs.whisperSize,
      whisperLanguage: _whisperLanguage(sourceIso, pack),
      englishToTarget: englishToTarget,
    );
  }

  /// Prompt language for whisper.cpp.
  ///
  /// `auto` is what classified Wolof speech as English (p ≈ 0.95). Use the
  /// pack token when it names a real language, otherwise the spoken ISO when
  /// Whisper has that token.
  String _whisperLanguage(String sourceIso, WhisperSpecialistPack? pack) {
    final fromPack = pack?.whisperLang.toLowerCase();
    if (fromPack != null && fromPack.isNotEmpty && fromPack != 'auto') {
      return fromPack;
    }
    if (_whisperLanguageIds.contains(sourceIso)) return sourceIso;
    return 'auto';
  }

  /// ISO 639-1 codes whisper.cpp accepts. Wolof (`wo`) is not in this set.
  static const Set<String> _whisperLanguageIds = {
    'en',
    'fr',
    'es',
    'de',
    'it',
    'pt',
    'nl',
    'ru',
    'zh',
    'ja',
    'ko',
    'ar',
    'sw',
    'yo',
    'ha',
  };

  WhisperSpecialistPack? _downloadablePackForIso(String iso) {
    for (final pack in kWhisperSpecialistPacks) {
      if (pack.iso.toLowerCase() == iso && pack.isDownloadable) {
        return pack;
      }
    }
    return null;
  }
}
