import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:malinali/services/whisper_specialist_models.dart';

/// How speech reaches English for a voice turn.
enum VoiceSpeechStrategy {
  /// Fine-tune trained to emit English, then Marian English→target.
  englishOutputFineTune,

  /// Fine-tune trained to emit French (e.g. Fon→FR ST); no Marian when target is FR.
  frenchOutputFineTune,

  /// Fine-tune transcribes source language, Marian source→English, then English→target.
  transcribeThenMarianToEnglish,

  /// Source language direct to target language (no English bridge).
  directTranslate,

  /// Generic multilingual Whisper with translate-to-English, then Marian English→target.
  genericTranslate,

  /// Fast VOSK recognition (for FR/EN), then optional Marian bridge.
  vosk,
}

/// Resolved models for one voice turn.
class VoiceSpeechPlan {
  const VoiceSpeechPlan({
    required this.strategy,
    required this.whisperSize,
    required this.whisperLanguage,
    required this.sourceIso,
    this.specialist,
    this.sourceToEnglish,
    this.englishToTarget,
    this.voskModel,
  });

  final VoiceSpeechStrategy strategy;
  final VoiceWhisperSize whisperSize;
  final String sourceIso;

  /// whisper.cpp language token. Never `auto` for a language Whisper knows.
  /// Wolof has no `<|wo|>` token; the fine-tune is prompted with French.
  final String whisperLanguage;

  final WhisperSpecialistPack? specialist;
  final TranslationModel? sourceToEnglish;
  final TranslationModel? englishToTarget;
  final VoskModel? voskModel;

  WhisperModel get genericModel => whisperSize.model;

  bool get usesSpecialist => specialist != null;

  /// Generic Whisper is what the mic loads when this plan has no specialist
  /// and is not Vosk. Direct and cascade plans are included, so a missing
  /// speech model cannot look ready.
  bool get needsGenericWhisper =>
      specialist == null &&
      !(strategy == VoiceSpeechStrategy.vosk && voskModel != null);

  bool get needsVosk => strategy == VoiceSpeechStrategy.vosk;

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

    // Fon speech → French text (specialist ST). Product path is Fon→FR only.
    if (sourceIso == 'fon') {
      final pack = _downloadablePackForIso('fon');
      if (pack != null && pack.emitsFrench && targetIso == 'fr') {
        return VoiceSpeechPlan(
          strategy: VoiceSpeechStrategy.frenchOutputFineTune,
          whisperSize: prefs.whisperSize,
          sourceIso: sourceIso,
          whisperLanguage: pack.whisperLang,
          specialist: pack,
        );
      }
      // Unsupported target for Fon: still attach the pack so UI can explain.
      return VoiceSpeechPlan(
        strategy: VoiceSpeechStrategy.frenchOutputFineTune,
        whisperSize: prefs.whisperSize,
        sourceIso: sourceIso,
        whisperLanguage: pack?.whisperLang ?? 'fr',
        specialist: pack,
      );
    }

    // Spoken French: generic Whisper tiny/small with task=translate, so the
    // transcript is already English. No French→English Marian hop.
    if (sourceIso == 'fr') {
      final englishToTarget = targetIso == 'en' || targetIso == sourceIso
          ? null
          : curatedMarianForPair(sourceIso: 'en', targetIso: targetIso);
      return VoiceSpeechPlan(
        strategy: VoiceSpeechStrategy.genericTranslate,
        whisperSize: prefs.whisperSize,
        sourceIso: sourceIso,
        whisperLanguage: 'fr',
        englishToTarget: englishToTarget,
      );
    }

    // Fast Zipformer is English speech only, and not for English→French.
    final fastEnglish = prefs.useFastSttForEnFr &&
        sourceIso == 'en' &&
        targetIso != 'fr';
    if (fastEnglish) {
      final pack = whisperSpecialistById('icefall-en');
      if (pack != null && pack.isDownloadable) {
        final englishToTarget = targetIso == 'en'
            ? null
            : curatedMarianForPair(sourceIso: 'en', targetIso: targetIso);

        return VoiceSpeechPlan(
          strategy: VoiceSpeechStrategy.genericTranslate,
          whisperSize: prefs.whisperSize,
          sourceIso: sourceIso,
          whisperLanguage: sourceIso,
          specialist: pack,
          englishToTarget: englishToTarget,
        );
      }
    }

    // No downloadable fine-tune: generic Whisper emits English, then Marian
    // English→target. There is no source transcript to feed a wo→* model.
    if (sourceIso == 'wo' && _downloadablePackForIso(sourceIso) == null) {
      final englishToTarget = targetIso == 'en'
          ? null
          : curatedMarianForPair(sourceIso: 'en', targetIso: targetIso);
      return VoiceSpeechPlan(
        strategy: VoiceSpeechStrategy.genericTranslate,
        whisperSize: prefs.whisperSize,
        sourceIso: sourceIso,
        whisperLanguage: 'fr',
        englishToTarget: englishToTarget,
      );
    }

    // 1. Try a direct Marian model for source -> target
    final directModel = curatedMarianForPair(sourceIso: sourceIso, targetIso: targetIso);
    if (directModel != null) {
      // We still need a Whisper pack to transcribe the source
      final pack = _downloadablePackForIso(sourceIso, includeIcefall: fastEnglish);
      return VoiceSpeechPlan(
        strategy: VoiceSpeechStrategy.directTranslate,
        whisperSize: prefs.whisperSize,
        sourceIso: sourceIso,
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

    final pack = _downloadablePackForIso(
      sourceIso,
      includeIcefall: fastEnglish,
    );

    if (pack != null && pack.emitsEnglish) {
      return VoiceSpeechPlan(
        strategy: VoiceSpeechStrategy.englishOutputFineTune,
        whisperSize: prefs.whisperSize,
        sourceIso: sourceIso,
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
          sourceIso: sourceIso,
          whisperLanguage: _whisperLanguage(sourceIso, pack),
          specialist: pack,
          sourceToEnglish: sourceToEnglish,
          englishToTarget: englishToTarget,
        );
      }
    }

    // No specialist pack (e.g. French): still bridge through English when
    // both hops exist. FR→WO uses this instead of the BLEU 9.3 direct model.
    if (englishToTarget != null) {
      final sourceToEnglish = curatedMarianForPair(
        sourceIso: sourceIso,
        targetIso: 'en',
      );
      if (sourceToEnglish != null) {
        return VoiceSpeechPlan(
          strategy: VoiceSpeechStrategy.transcribeThenMarianToEnglish,
          whisperSize: prefs.whisperSize,
          sourceIso: sourceIso,
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
      sourceIso: sourceIso,
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

  WhisperSpecialistPack? _downloadablePackForIso(String iso, {bool includeIcefall = false}) {
    for (final pack in kWhisperSpecialistPacks) {
      if (pack.iso.toLowerCase() == iso && pack.isDownloadable) {
        if (pack.id.startsWith('icefall-') && !includeIcefall) continue;
        return pack;
      }
    }
    return null;
  }
}
