import 'package:flutter/foundation.dart';
import 'package:malinali/services/document_translation_service.dart';
import 'package:malinali/services/marian_runtime.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_speech_resolver.dart';
import 'package:malinali/services/whisper_speech_service.dart';
import 'package:marian_flutter/marian_flutter.dart';

/// One voice turn shown in the chat (may still be translating).
class VoiceTurn {
  const VoiceTurn({
    required this.wavPath,
    this.englishText,
    required this.targetText,
    this.sourceTranscript,
    this.isTranslating = false,
    this.timings,
  });

  final String wavPath;
  final String? englishText;
  final String targetText;

  /// Source-language transcript when the cascade path ran.
  final String? sourceTranscript;

  /// True while Marian hops are still running after Whisper finished.
  final bool isTranslating;

  /// Stage durations for the completed (or last) run, when measured.
  final VoiceStageTimings? timings;

  VoiceTurn copyWith({
    String? wavPath,
    String? englishText,
    String? targetText,
    String? sourceTranscript,
    bool? isTranslating,
    VoiceStageTimings? timings,
    bool clearEnglishText = false,
  }) {
    return VoiceTurn(
      wavPath: wavPath ?? this.wavPath,
      englishText: clearEnglishText ? null : (englishText ?? this.englishText),
      targetText: targetText ?? this.targetText,
      sourceTranscript: sourceTranscript ?? this.sourceTranscript,
      isTranslating: isTranslating ?? this.isTranslating,
      timings: timings ?? this.timings,
    );
  }
}

/// Wall-clock stages for one voice turn (milliseconds).
class VoiceStageTimings {
  const VoiceStageTimings({
    required this.whisperMs,
    required this.releaseMs,
    required this.marianHops,
    required this.totalMs,
  });

  final int whisperMs;
  final int releaseMs;
  final List<MarianHopTiming> marianHops;
  final int totalMs;

  int get marianTotalMs =>
      marianHops.fold(0, (sum, h) => sum + h.loadMs + h.translateMs);

  /// Whisper vs Marian share of measured work (excludes UI).
  String get bottleneck {
    if (whisperMs >= marianTotalMs) return 'whisper';
    return 'marian';
  }

  String get summaryLine {
    final hops = marianHops
        .map((h) => '${h.modelId.split('/').last}'
            '(load=${h.loadMs}ms tx=${h.translateMs}ms)')
        .join(' ');
    return 'Voice timings bottleneck=$bottleneck '
        'whisper=${whisperMs}ms release=${releaseMs}ms '
        'marian=${marianTotalMs}ms [$hops] total=${totalMs}ms';
  }
}

class MarianHopTiming {
  const MarianHopTiming({
    required this.modelId,
    required this.loadMs,
    required this.translateMs,
  });

  final String modelId;
  final int loadMs;
  final int translateMs;
}

/// Text translation used by [VoiceTurnPipeline]. Tests inject this so the
/// cascade can run without loading Candle.
typedef VoiceMarianTranslate = Future<String> Function(
  TranslationModel model,
  String text,
);

/// Fired as soon as Whisper returns text (before Marian).
typedef VoiceTranscriptReady = void Function(VoiceTurn partial);

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

  Future<({MarianService service, int loadMs})> _loadMarian(
    TranslationModel model, {
    void Function(String status)? onStatus,
  }) async {
    final runtime = MarianRuntime.instance;
    if (runtime.isReady && runtime.model?.modelId == model.modelId) {
      return (service: runtime.marian!, loadMs: 0);
    }
    onStatus?.call('Chargement ${model.displayName}…');
    // Drop the previous Candle session before loading another ~300 Mo pack.
    // MarianService has no dispose; clearing the Dart ref lets the FRB object
    // drop so native weights can free before the next mmap.
    runtime.clear();
    final dir = await modelService.downloadModel(model);
    final sw = Stopwatch()..start();
    final marian = await MarianService.loadFromDirectory(dir.path);
    debugPrint(
      'Marian load ${model.modelId} in ${sw.elapsedMilliseconds} ms',
    );
    runtime.attach(marian, model);
    await MarianRuntime.saveLastSelectedModel(model);
    return (service: marian, loadMs: sw.elapsedMilliseconds);
  }

  Future<({String text, MarianHopTiming timing})> _translate(
    TranslationModel model,
    String text, {
    void Function(String status)? onStatus,
  }) async {
    final injected = translate;
    final prepared = model.prepareSourceText(text);
    if (injected != null) {
      final out = await injected(model, prepared);
      return (
        text: out,
        timing: MarianHopTiming(
          modelId: model.modelId,
          loadMs: 0,
          translateMs: 0,
        ),
      );
    }

    final loaded = await _loadMarian(model, onStatus: onStatus);
    onStatus?.call('Traduction ${model.displayName}…');
    final txSw = Stopwatch()..start();
    final service = DocumentTranslationService(splitSentences: true);
    // For voice, we join with spaces to keep the transcript natural.
    final result = await service.translateDocument(
      sourceText: text,
      marian: loaded.service,
      config: kDocumentTranslationConfig,
      prepareSource: (chunk) => model.prepareSourceText(chunk),
      joiner: ' ',
    );
    return (
      text: _stripPrefix(result.text.trim()),
      timing: MarianHopTiming(
        modelId: model.modelId,
        loadMs: loaded.loadMs,
        translateMs: txSw.elapsedMilliseconds,
      ),
    );
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
    void Function(double? progress)? onProgress,
  }) async {
    if (plan.strategy == VoiceSpeechStrategy.genericTranslate ||
        (plan.strategy == VoiceSpeechStrategy.englishOutputFineTune &&
            plan.specialist == null)) {
      onStatus?.call('Téléchargement du modèle vocal…');
      onProgress?.call(null);
      await whisper.setGenericModel(plan.genericModel);
      await whisper.setActivePack(null);
      await whisper.ensureGenericModel(plan.genericModel);
    } else if (plan.specialist != null) {
      onStatus?.call('Téléchargement du modèle vocal…');
      onProgress?.call(null);
      await whisper.setActivePack(plan.specialist);
      await whisper.downloadSpecialist(
        plan.specialist!,
        onProgress: (received, total) {
          if (total > 0) {
            onProgress?.call(received / total);
          }
        },
      );
    }

    for (final model in plan.marianDownloads) {
      onStatus?.call('Téléchargement ${model.displayName}…');
      onProgress?.call(null);
      await modelService.downloadModel(
        model,
        onProgress: (received, total) {
          if (total > 0) {
            onProgress?.call(received / total);
          }
        },
      );
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

  /// First Marian hop for a plan (cascade: source→en; otherwise en→target).
  /// Prefer this for preload so we do not park en→fr before Whisper runs.
  static TranslationModel? firstMarianHop(VoiceSpeechPlan plan) {
    return plan.sourceToEnglish ?? plan.englishToTarget;
  }

  Future<VoiceTurn> run({
    required String wavPath,
    required VoiceSpeechPlan plan,
    void Function(String status)? onStatus,
    VoiceTranscriptReady? onTranscriptReady,
  }) async {
    final totalSw = Stopwatch()..start();
    final hops = <MarianHopTiming>[];

    if (plan.specialist != null) {
      await whisper.setActivePack(plan.specialist);
    } else {
      await whisper.setGenericModel(plan.genericModel);
      await whisper.setActivePack(null);
    }

    // Free a parked Marian before Whisper (cascade used to preload en→fr, then
    // keep Whisper + load wo→en → OOM/thrash on phones).
    MarianRuntime.instance.clear();

    debugPrint(
      'Whisper STT language=${plan.whisperLanguage} '
      'translate=${plan.translateToEnglish} '
      'pack=${plan.specialist?.id ?? plan.genericModel.modelName}',
    );
    onStatus?.call('Transcription…');
    final sttSw = Stopwatch()..start();
    final raw = (await whisper.transcribeWav(
      wavPath,
      language: plan.whisperLanguage,
      translate: plan.translateToEnglish,
    )).trim();
    final whisperMs = sttSw.elapsedMilliseconds;
    debugPrint('Whisper STT done in $whisperMs ms');

    // Whisper keep_model_loaded parks ~250 Mo; drop it before Candle.
    onStatus?.call('Libération du modèle vocal…');
    final releaseSw = Stopwatch()..start();
    await whisper.releaseParkedModel();
    final releaseMs = releaseSw.elapsedMilliseconds;

    if (raw.isEmpty) {
      throw StateError('Aucune parole détectée.');
    }

    // Surface Whisper output immediately so the UI is not blank during Marian.
    final needsMarian = plan.englishToTarget != null ||
        plan.strategy == VoiceSpeechStrategy.directTranslate ||
        plan.strategy == VoiceSpeechStrategy.transcribeThenMarianToEnglish;
    final partial = VoiceTurn(
      wavPath: wavPath,
      sourceTranscript: raw,
      targetText: '',
      isTranslating: needsMarian,
    );
    onTranscriptReady?.call(partial);
    if (needsMarian) {
      onStatus?.call('Traduction…');
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
        final en = await _translate(toEn, raw, onStatus: onStatus);
        hops.add(en.timing);
        englishText = en.text.trim();
        if (englishText.isEmpty) {
          throw StateError('Traduction vers l’anglais vide.');
        }
        onTranscriptReady?.call(
          partial.copyWith(
            sourceTranscript: sourceTranscript,
            englishText: englishText,
            isTranslating: plan.englishToTarget != null,
          ),
        );
        break;
      case VoiceSpeechStrategy.directTranslate:
        sourceTranscript = raw;
        final toTarget = plan.sourceToEnglish; // Reusing field for source -> target
        if (toTarget == null) {
          throw StateError('Modèle direct source → cible manquant.');
        }
        final out = await _translate(toTarget, raw, onStatus: onStatus);
        hops.add(out.timing);
        final targetText = out.text.trim();
        if (targetText.isEmpty) {
          throw StateError('Traduction cible vide.');
        }
        final timings = VoiceStageTimings(
          whisperMs: whisperMs,
          releaseMs: releaseMs,
          marianHops: hops,
          totalMs: totalSw.elapsedMilliseconds,
        );
        debugPrint(timings.summaryLine);
        return VoiceTurn(
          wavPath: wavPath,
          targetText: targetText,
          sourceTranscript: sourceTranscript,
          timings: timings,
        );
    }

    final toTarget = plan.englishToTarget;
    if (toTarget == null) {
      final timings = VoiceStageTimings(
        whisperMs: whisperMs,
        releaseMs: releaseMs,
        marianHops: hops,
        totalMs: totalSw.elapsedMilliseconds,
      );
      debugPrint(timings.summaryLine);
      return VoiceTurn(
        wavPath: wavPath,
        englishText: englishText,
        targetText: englishText ?? sourceTranscript ?? '',
        sourceTranscript: sourceTranscript,
        timings: timings,
      );
    }

    final fr = await _translate(
      toTarget,
      englishText ?? sourceTranscript ?? '',
      onStatus: onStatus,
    );
    hops.add(fr.timing);
    final targetText = fr.text.trim();
    if (targetText.isEmpty) {
      throw StateError('Traduction cible vide.');
    }

    final timings = VoiceStageTimings(
      whisperMs: whisperMs,
      releaseMs: releaseMs,
      marianHops: hops,
      totalMs: totalSw.elapsedMilliseconds,
    );
    debugPrint(timings.summaryLine);
    return VoiceTurn(
      wavPath: wavPath,
      englishText: englishText,
      targetText: targetText,
      sourceTranscript: sourceTranscript,
      timings: timings,
    );
  }
}
