import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:malinali/services/audio_transcription_service.dart';
import 'package:malinali/services/document_translation_service.dart';
import 'package:malinali/services/marian_runtime.dart';
import 'package:malinali/services/speech_recognition_service.dart';
import 'package:malinali/services/text_translator.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_pcm_stream.dart';
import 'package:malinali/services/voice_speech_resolver.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:malinali/services/whisper_speech_service.dart';
import 'package:malinali/services/wolof_spanish_phonetics.dart';

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
    this.engine = 'whisper',
  });

  final int whisperMs;
  final int releaseMs;
  final List<MarianHopTiming> marianHops;
  final int totalMs;
  final String engine;

  int get marianTotalMs =>
      marianHops.fold(0, (sum, h) => sum + h.loadMs + h.translateMs);

  /// Whisper vs Marian share of measured work (excludes UI).
  String get bottleneck {
    if (whisperMs >= marianTotalMs) return engine;
    return 'marian';
  }

  /// Debug-only timing dump. Empty in release builds.
  String get summaryLine {
    if (!kDebugMode) return '';
    final hops = marianHops
        .map((h) => '${h.modelId.split('/').last}'
            '(load=${h.loadMs}ms tx=${h.translateMs}ms)')
        .join(' ');
    return 'Voice timings engine=$engine bottleneck=$bottleneck '
        'stt=${whisperMs}ms release=${releaseMs}ms '
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
  /// When set, overrides `TextTranslatorLoader.load` so tests can inspect
  /// `DecodeConfig` passed to [TextTranslator.translate].
  final Future<TextTranslator> Function(
    TranslationModel model,
    String directory,
  )? loadTranslator;

  VoiceTurnPipeline({
    required this.whisper,
    required this.modelService,
    VoskModelService? voskModelService,
    SpeechRecognitionService? speechService,
    this.resolver = const VoiceSpeechResolver(),
    this.translate,
    this.loadTranslator,
    this.openPcmFeed,
  })  : _voskModelService = voskModelService ?? VoskModelService(),
        _speechService = speechService ??
            SpeechRecognitionService(
              modelService: voskModelService ?? VoskModelService(),
            );

  final WhisperSpeechService whisper;
  final TranslationModelService modelService;
  final VoskModelService _voskModelService;
  final SpeechRecognitionService _speechService;
  final VoiceSpeechResolver resolver;

  /// When set, skips on-device Marian and calls this instead.
  final VoiceMarianTranslate? translate;

  /// When set, [streamPcm] uses this instead of Vosk / Whisper / Sherpa.
  final Future<VoicePcmFeed> Function(VoiceSpeechPlan plan)? openPcmFeed;

  Future<({TextTranslator service, int loadMs})> _loadMarian(
    TranslationModel model, {
    void Function(String status)? onStatus,
  }) async {
    final runtime = MarianRuntime.instance;
    if (runtime.isReady && runtime.model?.modelId == model.modelId) {
      return (service: runtime.translator!, loadMs: 0);
    }
    onStatus?.call('Chargement ${model.displayName}…');
    // Drop the previous session before loading another ~300 Mo pack.
    runtime.clear();
    final dir = await modelService.downloadModel(model);
    final sw = Stopwatch()..start();
    final loader = loadTranslator;
    final marian = loader != null
        ? await loader(model, dir.path)
        : await TextTranslatorLoader.load(
            model: model,
            directory: dir.path,
          );
    debugPrint(
      'Marian load ${model.modelId} in ${sw.elapsedMilliseconds} ms',
    );
    runtime.attach(marian, model);
    try {
      await MarianRuntime.saveLastSelectedModel(model);
    } catch (_) {
      // Ignore path_provider errors in pure unit tests.
    }
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
      config: kVoiceDecodeConfig,
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
    final List<Future<void> Function(void Function(double? p))> tasks = [];

    // 1. Speech model task
    if (plan.strategy == VoiceSpeechStrategy.vosk && plan.voskModel != null) {
      if (!await _voskModelService.isModelDownloaded(plan.voskModel!)) {
        tasks.add((pCall) async {
          onStatus?.call('Téléchargement du modèle vocal…');
          await _voskModelService.downloadModel(
            plan.voskModel!,
            onProgress: (received, total) {
              if (total > 0) pCall(received / total);
            },
          );
        });
      }
    } else if (plan.specialist != null) {
      if (!await whisper.isSpecialistDownloaded(plan.specialist!)) {
        tasks.add((pCall) async {
          onStatus?.call('Téléchargement du modèle vocal…');
          await whisper.setActivePack(plan.specialist);
          await whisper.downloadSpecialist(
            plan.specialist!,
            onProgress: (received, total) {
              if (total > 0) pCall(received / total);
            },
          );
        });
      }
    } else if (plan.needsGenericWhisper &&
        !await whisper.isGenericDownloaded(plan.genericModel)) {
      tasks.add((pCall) async {
        onStatus?.call('Téléchargement du modèle vocal…');
        await whisper.setGenericModel(plan.genericModel);
        await whisper.setActivePack(null);
        await whisper.ensureGenericModel(
          plan.genericModel,
          (received, total) {
            if (total > 0) pCall(received / total);
          },
        );
      });
    }

    // 2. Marian model tasks
    final marian = plan.marianDownloads;
    for (var i = 0; i < marian.length; i++) {
      final model = marian[i];
      if (await modelService.isModelDownloaded(model)) continue;

      final step = marian.length == 1 ? '' : ' (${i + 1}/${marian.length})';
      tasks.add((pCall) async {
        onStatus?.call('Téléchargement du modèle de traduction$step…');
        await modelService.downloadModel(
          model,
          onProgress: (received, total) {
            if (total > 0) pCall(received / total);
          },
        );
      });
    }

    if (tasks.isEmpty) {
      if (!await modelsReady(plan)) {
        throw StateError('Les modèles de cette paire ne sont pas prêts.');
      }
      return;
    }

    // Execute tasks with global progress
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      await task((p) {
        if (onProgress != null) {
          // p is 0..1 for the current task
          final globalP = (i + (p ?? 0)) / tasks.length;
          onProgress(globalP);
        }
      });
    }

    if (!await modelsReady(plan)) {
      throw StateError('Les modèles de cette paire ne sont pas prêts.');
    }
  }

  Future<bool> modelsReady(VoiceSpeechPlan plan) async {
    if (plan.strategy == VoiceSpeechStrategy.vosk && plan.voskModel != null) {
      if (!await _voskModelService.isModelDownloaded(plan.voskModel!)) {
        return false;
      }
    } else if (plan.specialist != null) {
      if (!await whisper.isSpecialistDownloaded(plan.specialist!)) return false;
    } else if (plan.needsGenericWhisper) {
      if (!await whisper.isGenericDownloaded(plan.genericModel)) return false;
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

    String raw = '';
    int sttMs = 0;
    int releaseMs = 0;
    String engine = plan.specialist?.id.contains('icefall') == true ? 'sherpa-icefall' : 'whisper';

    if (plan.strategy == VoiceSpeechStrategy.vosk && plan.voskModel != null) {
      engine = 'vosk';
      onStatus?.call('Transcription (Vosk)…');
      final sw = Stopwatch()..start();
      final transcriber = VoskWaveformTranscriber(
        speech: _speechService,
        model: plan.voskModel!,
      );
      final service = AudioTranscriptionService(transcriber: transcriber);
      final result = await service.transcribeFile(
        File(wavPath),
        onProgress: (p) {
          // Internal feedback if needed
        },
      );
      raw = result.text.trim();
      sttMs = sw.elapsedMilliseconds;
      debugPrint('Vosk STT done in $sttMs ms');
    } else {
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
      raw = (await whisper.transcribeWav(
        wavPath,
        language: plan.whisperLanguage,
        translate: plan.translateToEnglish,
      )).trim();

      if (plan.sourceIso == 'wo') {
        raw = wolofToSpanishPhonetics(raw);
      }

      sttMs = sttSw.elapsedMilliseconds;
      debugPrint('Whisper STT done in $sttMs ms');

      // Whisper keep_model_loaded parks the ASR graphs; drop it before Candle.
      onStatus?.call('Libération du modèle vocal…');
      final releaseSw = Stopwatch()..start();
      await whisper.releaseParkedModel();
      releaseMs = releaseSw.elapsedMilliseconds;
    }

    if (raw.isEmpty) {
      throw StateError('Aucune parole détectée.');
    }

    // Surface STT output immediately so the UI is not blank during Marian.
    final needsMarian = plan.englishToTarget != null ||
        plan.strategy == VoiceSpeechStrategy.directTranslate ||
        plan.strategy == VoiceSpeechStrategy.transcribeThenMarianToEnglish ||
        (plan.strategy == VoiceSpeechStrategy.vosk &&
            plan.englishToTarget != null);
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
      case VoiceSpeechStrategy.vosk:
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
        MarianRuntime.instance.clear();
        final targetText = out.text.trim();
        if (targetText.isEmpty) {
          throw StateError('Traduction cible vide.');
        }
        final timings = VoiceStageTimings(
          whisperMs: sttMs,
          releaseMs: releaseMs,
          marianHops: hops,
          totalMs: totalSw.elapsedMilliseconds,
          engine: engine,
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
      MarianRuntime.instance.clear();
      final timings = VoiceStageTimings(
        whisperMs: sttMs,
        releaseMs: releaseMs,
        marianHops: hops,
        totalMs: totalSw.elapsedMilliseconds,
        engine: engine,
      );
      debugPrint(timings.summaryLine);
      return VoiceTurn(
        wavPath: wavPath,
        englishText: englishText,
        targetText: englishText ?? sourceTranscript,
        sourceTranscript: sourceTranscript,
        timings: timings,
      );
    }

    // Drop the intermediate source→en session before loading en→target (~925 MB ONNX).
    MarianRuntime.instance.clear();
    final fr = await _translate(
      toTarget,
      englishText ?? sourceTranscript,
      onStatus: onStatus,
    );
    hops.add(fr.timing);
    MarianRuntime.instance.clear();
    final targetText = fr.text.trim();
    if (targetText.isEmpty) {
      throw StateError('Traduction cible vide.');
    }

    final timings = VoiceStageTimings(
      whisperMs: sttMs,
      releaseMs: releaseMs,
      marianHops: hops,
      totalMs: totalSw.elapsedMilliseconds,
      engine: engine,
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

  /// Push 16 kHz mono PCM through the streaming recognizer [plan] selects.
  ///
  /// Vosk, Whisper, and Sherpa transducer all enter here. This does not call
  /// a whole-file transcribe.
  Future<String> streamPcm({
    required Uint8List pcm16,
    required VoiceSpeechPlan plan,
    void Function(String partial)? onPartial,
  }) async {
    final opener = openPcmFeed ?? _openDefaultPcmFeed;
    final feed = await opener(plan);
    const chunkBytes = 8000;
    var offset = 0;
    while (offset < pcm16.length) {
      final end = offset + chunkBytes < pcm16.length
          ? offset + chunkBytes
          : pcm16.length;
      await feed.feed(Uint8List.sublistView(pcm16, offset, end));
      final partial = (await feed.latestPartial())?.trim() ?? '';
      if (partial.isNotEmpty) onPartial?.call(partial);
      offset = end;
    }
    var raw = (await feed.finish()).trim();
    if (plan.sourceIso == 'wo' && feed.engine != 'vosk') {
      raw = wolofToSpanishPhonetics(raw);
    }
    if (feed.engine != 'vosk') {
      await whisper.releaseParkedModel();
    }
    if (raw.isEmpty) {
      throw StateError('Aucune parole détectée.');
    }
    return raw;
  }

  Future<VoicePcmFeed> _openDefaultPcmFeed(VoiceSpeechPlan plan) async {
    if (plan.strategy == VoiceSpeechStrategy.vosk && plan.voskModel != null) {
      await _speechService.initialize(model: plan.voskModel);
      await _speechService.resetRecognizer();
      return VoskPcmFeed(_speechService);
    }
    if (plan.specialist != null) {
      await whisper.setActivePack(plan.specialist);
    } else {
      await whisper.setGenericModel(plan.genericModel);
      await whisper.setActivePack(null);
    }
    MarianRuntime.instance.clear();
    final session = await whisper.openPcmSession(
      language: plan.whisperLanguage,
      translate: plan.translateToEnglish,
    );
    return SherpaPcmFeed(session, engine: voiceStreamEngine(plan));
  }

  /// Continues a turn that already has a transcript (finishes Marian hops).
  Future<VoiceTurn> finalizeTurn({
    required VoiceTurn turn,
    required VoiceSpeechPlan plan,
    void Function(String status)? onStatus,
    int whisperMs = 0,
    String engine = 'whisper',
  }) async {
    final totalSw = Stopwatch()..start();
    final raw = turn.sourceTranscript ?? '';
    final hops = <MarianHopTiming>[];

    String? sourceTranscript = raw;
    String? englishText;

    switch (plan.strategy) {
      case VoiceSpeechStrategy.vosk:
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
        break;
      case VoiceSpeechStrategy.directTranslate:
        sourceTranscript = raw;
        final toTarget = plan.sourceToEnglish;
        if (toTarget == null) {
          throw StateError('Modèle direct source → cible manquant.');
        }
        final out = await _translate(toTarget, raw, onStatus: onStatus);
        hops.add(out.timing);
        final targetText = out.text.trim();
        final timings = VoiceStageTimings(
          whisperMs: whisperMs,
          releaseMs: 0,
          marianHops: hops,
          totalMs: totalSw.elapsedMilliseconds,
          engine: engine,
        );
        return turn.copyWith(
          targetText: targetText,
          sourceTranscript: sourceTranscript,
          timings: timings,
          isTranslating: false,
        );
    }

    final toTarget = plan.englishToTarget;
    if (toTarget == null) {
      final timings = VoiceStageTimings(
        whisperMs: whisperMs,
        releaseMs: 0,
        marianHops: hops,
        totalMs: totalSw.elapsedMilliseconds,
        engine: engine,
      );
      return turn.copyWith(
        englishText: englishText,
        targetText: englishText ?? sourceTranscript,
        sourceTranscript: sourceTranscript,
        timings: timings,
        isTranslating: false,
      );
    }

    final fr = await _translate(
      toTarget,
      englishText ?? sourceTranscript,
      onStatus: onStatus,
    );
    hops.add(fr.timing);
    final targetText = fr.text.trim();

    final timings = VoiceStageTimings(
      whisperMs: whisperMs,
      releaseMs: 0,
      marianHops: hops,
      totalMs: totalSw.elapsedMilliseconds,
      engine: engine,
    );
    return turn.copyWith(
      englishText: englishText,
      targetText: targetText,
      sourceTranscript: sourceTranscript,
      timings: timings,
      isTranslating: false,
    );
  }
}
