import 'package:flutter/foundation.dart';
import 'package:malinali/services/marian_runtime.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_speech_resolver.dart';
import 'package:malinali/services/whisper_speech_service.dart';
import 'package:marian_flutter/marian_flutter.dart';

/// One completed voice turn shown in the chat.
class VoiceTurn {
  const VoiceTurn({
    required this.wavPath,
    this.englishText,
    required this.targetText,
    this.sourceTranscript,
  });

  final String wavPath;
  final String? englishText;
  final String targetText;

  /// Source-language transcript when the cascade path ran.
  final String? sourceTranscript;
}

/// Text translation used by [VoiceTurnPipeline]. Tests inject this so the
/// cascade can run without loading Candle.
typedef VoiceMarianTranslate = Future<String> Function(
  TranslationModel model,
  String text,
);

/// Runs speech → English → Marian English→target for a recorded WAV.
class VoiceTurnPipeline {
  VoiceTurnPipeline({
    required this.whisper,
    required this.modelService,
    this.resolver = const VoiceSpeechResolver(),
    this.translate,
  });

  final WhisperSpeechService whisper;
  final TranslationModelService modelService;
  final VoiceSpeechResolver resolver;

  /// When set, skips on-device Marian and calls this instead.
  final VoiceMarianTranslate? translate;

  Future<MarianService> _loadMarian(TranslationModel model) async {
    final runtime = MarianRuntime.instance;
    if (runtime.isReady && runtime.model?.modelId == model.modelId) {
      return runtime.marian!;
    }
    final dir = await modelService.downloadModel(model);
    final marian = await MarianService.loadFromDirectory(dir.path);
    runtime.attach(marian, model);
    await MarianRuntime.saveLastSelectedModel(model);
    return marian;
  }

  Future<String> _translate(TranslationModel model, String text) async {
    final injected = translate;
    final prepared = model.prepareSourceText(text);
    String result;
    if (injected != null) {
      result = await injected(model, prepared);
    } else {
      final marian = await _loadMarian(model);
      result = await marian.translate(prepared);
    }
    return _stripPrefix(result.trim());
  }

  String _stripPrefix(String text) {
    // Strips common Marian prefixes from output (e.g. ">>wol<< ")
    if (text.startsWith('>>') && text.contains('<<')) {
      final end = text.indexOf('<<') + 2;
      return text.substring(end).trim();
    }
    return text;
  }

  Future<void> ensureModels(
    VoiceSpeechPlan plan, {
    void Function(String status)? onStatus,
  }) async {
    if (plan.strategy == VoiceSpeechStrategy.genericTranslate ||
        (plan.strategy == VoiceSpeechStrategy.englishOutputFineTune &&
            plan.specialist == null)) {
      onStatus?.call('Téléchargement du modèle vocal…');
      await whisper.setGenericModel(plan.genericModel);
      await whisper.setActivePack(null);
      await whisper.ensureGenericModel(plan.genericModel);
    } else if (plan.specialist != null) {
      onStatus?.call('Téléchargement du modèle vocal…');
      await whisper.setActivePack(plan.specialist);
      await whisper.ensureModel();
    }

    for (final model in plan.marianDownloads) {
      onStatus?.call('Téléchargement ${model.displayName}…');
      await modelService.downloadModel(model);
    }
  }

  Future<bool> modelsReady(VoiceSpeechPlan plan) async {
    if (plan.strategy == VoiceSpeechStrategy.genericTranslate) {
      if (!await whisper.isGenericDownloaded(plan.genericModel)) return false;
    } else if (plan.specialist != null) {
      if (!await whisper.isSpecialistDownloaded(plan.specialist!)) return false;
    }
    for (final model in plan.marianDownloads) {
      if (!await modelService.isModelDownloaded(model)) return false;
    }
    return true;
  }

  Future<VoiceTurn> run({
    required String wavPath,
    required VoiceSpeechPlan plan,
  }) async {
    if (plan.specialist != null) {
      await whisper.setActivePack(plan.specialist);
    } else {
      await whisper.setGenericModel(plan.genericModel);
      await whisper.setActivePack(null);
    }

    debugPrint(
      'Whisper STT language=${plan.whisperLanguage} '
      'translate=${plan.translateToEnglish} '
      'pack=${plan.specialist?.id ?? plan.genericModel.modelName}',
    );
    final raw = (await whisper.transcribeWav(
      wavPath,
      language: plan.whisperLanguage,
      translate: plan.translateToEnglish,
    )).trim();
    if (raw.isEmpty) {
      throw StateError('Aucune parole détectée.');
    }

    String? sourceTranscript;
    String? englishText;

    switch (plan.strategy) {
      case VoiceSpeechStrategy.englishOutputFineTune:
      case VoiceSpeechStrategy.genericTranslate:
        // Spoken English (or translated to English by Whisper)
        sourceTranscript = raw;
        englishText = null;
        break;
      case VoiceSpeechStrategy.transcribeThenMarianToEnglish:
        sourceTranscript = raw;
        final toEn = plan.sourceToEnglish;
        if (toEn == null) {
          throw StateError('Modèle source → anglais manquant.');
        }
        englishText = (await _translate(toEn, raw)).trim();
        if (englishText.isEmpty) {
          throw StateError('Traduction vers l’anglais vide.');
        }
        break;
      case VoiceSpeechStrategy.directTranslate:
        sourceTranscript = raw;
        final toTarget = plan.sourceToEnglish; // Reusing field for source -> target
        if (toTarget == null) {
          throw StateError('Modèle direct source → cible manquant.');
        }
        final targetText = (await _translate(toTarget, raw)).trim();
        if (targetText.isEmpty) {
          throw StateError('Traduction cible vide.');
        }
        return VoiceTurn(
          wavPath: wavPath,
          targetText: targetText,
          sourceTranscript: sourceTranscript,
        );
    }

    final toTarget = plan.englishToTarget;
    if (toTarget == null) {
      return VoiceTurn(
        wavPath: wavPath,
        englishText: englishText,
        targetText: englishText ?? sourceTranscript ?? '',
        sourceTranscript: sourceTranscript,
      );
    }

    final targetText = (await _translate(toTarget, englishText ?? sourceTranscript ?? '')).trim();
    if (targetText.isEmpty) {
      throw StateError('Traduction cible vide.');
    }

    return VoiceTurn(
      wavPath: wavPath,
      englishText: englishText,
      targetText: targetText,
      sourceTranscript: sourceTranscript,
    );
  }
}
