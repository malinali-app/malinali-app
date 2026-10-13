import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/marian_runtime.dart';
import 'package:malinali/services/text_translator.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/voice_speech_resolver.dart';
import 'package:malinali/services/voice_turn_pipeline.dart';
import 'package:malinali/services/whisper_speech_service.dart';
import 'package:malinali/services/whisper_specialist_models.dart';

class _FakeWhisper extends Fake implements WhisperSpeechService {
  String transcript = 'hello';
  WhisperSpecialistPack? pack;
  WhisperModel generic = WhisperModel.small;
  String? language;
  bool? translate;
  int released = 0;

  @override
  Future<void> setActivePack(WhisperSpecialistPack? p) async {
    pack = p;
  }

  @override
  Future<void> setGenericModel(WhisperModel model) async {
    generic = model;
  }

  @override
  Future<String> ensureGenericModel([
    WhisperModel? model,
    void Function(int, int)? onProgress,
  ]) async =>
      'ok';

  @override
  Future<String> ensureModel() async => 'ok';

  @override
  Future<bool> isGenericDownloaded(WhisperModel model) async => true;

  @override
  Future<bool> isSpecialistDownloaded(WhisperSpecialistPack pack) async => true;

  @override
  Future<void> releaseParkedModel() async {
    released++;
  }

  @override
  Future<String> transcribeWav(
    String audioPath, {
    void Function(int percent)? onProgress,
    String? language,
    bool? translate,
  }) async {
    this.language = language;
    this.translate = translate;
    return transcript;
  }
}

class _FakeModelService extends Fake implements TranslationModelService {
  final Map<String, bool> downloaded = {};

  @override
  Future<bool> isModelDownloaded(TranslationModel model) async =>
      downloaded[model.modelId] ?? true;

  @override
  Future<Directory> downloadModel(
    TranslationModel model, {
    void Function(int received, int total)? onProgress,
  }) async {
    downloaded[model.modelId] = true;
    return Directory.systemTemp;
  }
}

class _TrackingTranslator implements TextTranslator {
  bool disposed = false;
  DecodeConfig? lastConfig;

  @override
  Future<String> translate(
    String text, {
    DecodeConfig config = kStreetDecodeConfig,
  }) async {
    lastConfig = config;
    return text;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  test('generic path: Whisper English then Marian English→target', () async {
    final whisper = _FakeWhisper()..transcript = 'good morning';
    final models = _FakeModelService();
    VoiceTurnPipeline(
      whisper: whisper,
      modelService: models,
    );
    final plan = const VoiceSpeechResolver().resolve(
      const VoicePreferences(
        sourceIso: 'sw',
        targetIso: 'fr',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );

    expect(plan.strategy, VoiceSpeechStrategy.genericTranslate);
    await whisper.setGenericModel(plan.genericModel);
    await whisper.setActivePack(null);
    final english = await whisper.transcribeWav('/tmp/a.wav');
    expect(english, 'good morning');
    expect(plan.englishToTarget?.modelId, 'malinali-app/opus-mt-en-fr-onnx');
    expect(whisper.pack, isNull);
  });

  test('Yoruba to French exposes the direct Marian model', () {
    final plan = const VoiceSpeechResolver().resolve(
      const VoicePreferences(
        sourceIso: 'yo',
        targetIso: 'fr',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    expect(plan.strategy, VoiceSpeechStrategy.directTranslate);
    expect(plan.marianDownloads.map((m) => m.modelId).toList(), [
      'malinali-app/opus-mt-yo-fr',
    ]);
  });

  test('Wolof cascade runs wolof-small then wo→en then en→fr', () async {
    final whisper = _FakeWhisper()..transcript = 'Nanga def';
    final seen = <String, String>{};
    final partials = <VoiceTurn>[];
    final plan = const VoiceSpeechResolver().resolve(VoicePreferences.defaults);
    final turn = await VoiceTurnPipeline(
      whisper: whisper,
      modelService: _FakeModelService(),
      translate: (model, text) async {
        seen[model.modelId] = text;
        switch (model.modelId) {
          case 'malinali-app/traduction-wolof-en-onnx':
            return 'How are you';
          case 'malinali-app/opus-mt-en-fr-onnx':
            return 'Comment allez-vous';
        }
        throw StateError('unexpected model ${model.modelId}');
      },
    ).run(
      wavPath: 'nanga_def.wav',
      plan: plan,
      onTranscriptReady: partials.add,
    );

    expect(plan.strategy, VoiceSpeechStrategy.transcribeThenMarianToEnglish);
    expect(plan.whisperLanguage, 'en');
    expect(plan.translateToEnglish, isFalse);
    expect(whisper.language, 'en');
    expect(whisper.translate, isFalse);
    expect(whisper.pack?.id, 'wolof-small');
    expect(whisper.released, 1);
    expect(seen['malinali-app/traduction-wolof-en-onnx'], 'Nanga def');
    expect(seen['malinali-app/opus-mt-en-fr-onnx'], 'How are you');
    expect(turn.sourceTranscript, 'Nanga def');
    expect(turn.englishText, 'How are you');
    expect(turn.targetText, 'Comment allez-vous');
    expect(turn.isTranslating, isFalse);
    expect(turn.timings, isNotNull);
    expect(partials, isNotEmpty);
    expect(partials.first.sourceTranscript, 'Nanga def');
    expect(partials.first.isTranslating, isTrue);
    expect(partials.first.targetText, isEmpty);
  });

  test('French→Wolof cascade transcribes French then fr→en then en→wo', () async {
    final whisper = _FakeWhisper()..transcript = 'Bonjour, comment allez-vous ?';
    final seen = <String, String>{};
    final plan = const VoiceSpeechResolver().resolve(
      const VoicePreferences(
        sourceIso: 'fr',
        targetIso: 'wo',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    final turn = await VoiceTurnPipeline(
      whisper: whisper,
      modelService: _FakeModelService(),
      translate: (model, text) async {
        seen[model.modelId] = text;
        switch (model.modelId) {
          case 'malinali-app/opus-mt_tiny_fra-eng-onnx':
            expect(text, 'Bonjour, comment allez-vous ?');
            return 'Hello, how are you?';
          case 'malinali-app/traduction-en-wolof-onnx':
            expect(text.startsWith('>>wol<< '), isTrue);
            return 'Nanga def';
        }
        throw StateError('unexpected model ${model.modelId}');
      },
    ).run(wavPath: 'bonjour.wav', plan: plan);

    expect(plan.strategy, VoiceSpeechStrategy.transcribeThenMarianToEnglish);
    expect(whisper.language, 'fr');
    expect(whisper.translate, isFalse);
    expect(whisper.pack, isNull);
    expect(seen['malinali-app/opus-mt_tiny_fra-eng-onnx'], 'Bonjour, comment allez-vous ?');
    expect(turn.sourceTranscript, 'Bonjour, comment allez-vous ?');
    expect(turn.englishText, 'Hello, how are you?');
    expect(turn.targetText, 'Nanga def');
  });

  test('recording gate waits until Marian packs are downloaded', () async {
    final models = _FakeModelService()
      ..downloaded['malinali-app/opus-mt_tiny_fra-eng-onnx'] = false
      ..downloaded['malinali-app/traduction-en-wolof-onnx'] = false;
    final pipeline = VoiceTurnPipeline(
      whisper: _FakeWhisper(),
      modelService: models,
    );
    final plan = const VoiceSpeechResolver().resolve(
      const VoicePreferences(
        sourceIso: 'fr',
        targetIso: 'wo',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    final statuses = <String>[];

    expect(await pipeline.modelsReady(plan), isFalse);
    await pipeline.ensureModels(plan, onStatus: statuses.add);
    expect(await pipeline.modelsReady(plan), isTrue);
    expect(
      models.downloaded['malinali-app/opus-mt_tiny_fra-eng-onnx'],
      isTrue,
    );
    expect(
      models.downloaded['malinali-app/traduction-en-wolof-onnx'],
      isTrue,
    );
    expect(
      statuses,
      contains(
        'Téléchargement ${plan.marianDownloads[0].displayName} (1/2)…',
      ),
    );
    expect(
      statuses,
      contains(
        'Téléchargement ${plan.marianDownloads[1].displayName} (2/2)…',
      ),
    );
  });

  test('first Marian hop for Wolof cascade is wo→en not en→fr', () {
    final plan = const VoiceSpeechResolver().resolve(VoicePreferences.defaults);
    expect(
      VoiceTurnPipeline.firstMarianHop(plan)?.modelId,
      'malinali-app/traduction-wolof-en-onnx',
    );
  });

  test('VoiceStageTimings bottleneck prefers the slower family', () {
    const whisperHeavy = VoiceStageTimings(
      whisperMs: 8000,
      releaseMs: 50,
      marianHops: [
        MarianHopTiming(modelId: 'a', loadMs: 500, translateMs: 200),
      ],
      totalMs: 9000,
    );
    expect(whisperHeavy.bottleneck, 'whisper');
    const marianHeavy = VoiceStageTimings(
      whisperMs: 1000,
      releaseMs: 50,
      marianHops: [
        MarianHopTiming(modelId: 'a', loadMs: 2000, translateMs: 500),
        MarianHopTiming(modelId: 'b', loadMs: 1500, translateMs: 400),
      ],
      totalMs: 5500,
    );
    expect(marianHeavy.bottleneck, 'marian');
    expect(marianHeavy.summaryLine, contains('bottleneck=marian'));
  });

  test('cascade clears MarianRuntime between hops and on turn completion', () async {
    final hop1Session = _TrackingTranslator();
    final hop2Session = _TrackingTranslator();
    final plan = const VoiceSpeechResolver().resolve(
      const VoicePreferences(
        sourceIso: 'fr',
        targetIso: 'wo',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    var hop = 0;
    await VoiceTurnPipeline(
      whisper: _FakeWhisper()..transcript = 'Je m\'appelle Pierre.',
      modelService: _FakeModelService(),
      translate: (model, text) async {
        hop++;
        if (hop == 1) {
          MarianRuntime.instance.attach(hop1Session, model);
          return 'My name is Peter.';
        }
        // Hop 1 must have been disposed before hop 2 loads.
        expect(hop1Session.disposed, isTrue);
        expect(MarianRuntime.instance.isReady, isFalse);
        MarianRuntime.instance.attach(hop2Session, model);
        return 'Maa ngi tudd Pierre.';
      },
    ).run(wavPath: 'pierre.wav', plan: plan);

    expect(hop2Session.disposed, isTrue);
    expect(MarianRuntime.instance.isReady, isFalse);
  });

  test('voice pipeline uses greedy kVoiceDecodeConfig (numBeams=1) for Marian hops', () async {
    final translator = _TrackingTranslator();
    final plan = const VoiceSpeechResolver().resolve(
      const VoicePreferences(
        sourceIso: 'sw',
        targetIso: 'fr',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );

    await VoiceTurnPipeline(
      whisper: _FakeWhisper()..transcript = 'Hello world.',
      modelService: _FakeModelService(),
      loadTranslator: (_, __) async => translator,
    ).run(wavPath: 'hello.wav', plan: plan);

    expect(translator.lastConfig, kVoiceDecodeConfig);
    expect(translator.lastConfig?.numBeams, 1);
    expect(translator.disposed, isTrue);
  });
}
