import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/voice_speech_resolver.dart';
import 'package:malinali/services/voice_turn_pipeline.dart';
import 'package:malinali/services/whisper_speech_service.dart';
import 'package:malinali/services/whisper_specialist_models.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

class _FakeWhisper extends Fake implements WhisperSpeechService {
  String transcript = 'hello';
  WhisperSpecialistPack? pack;
  WhisperModel generic = WhisperModel.small;
  String? language;
  bool? translate;

  @override
  Future<void> setActivePack(WhisperSpecialistPack? p) async {
    pack = p;
  }

  @override
  Future<void> setGenericModel(WhisperModel model) async {
    generic = model;
  }

  @override
  Future<String> ensureGenericModel([WhisperModel? model]) async => 'ok';

  @override
  Future<String> ensureModel() async => 'ok';

  @override
  Future<bool> isGenericDownloaded(WhisperModel model) async => true;

  @override
  Future<bool> isSpecialistDownloaded(WhisperSpecialistPack pack) async => true;

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
  Future<Directory> downloadModel(TranslationModel model) async {
    downloaded[model.modelId] = true;
    return Directory.systemTemp;
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
    expect(plan.englishToTarget?.modelId, 'Xenova/opus-mt-en-fr');
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
    final plan = const VoiceSpeechResolver().resolve(VoicePreferences.defaults);
    final turn = await VoiceTurnPipeline(
      whisper: whisper,
      modelService: _FakeModelService(),
      translate: (model, text) async {
        seen[model.modelId] = text;
        switch (model.modelId) {
          case 'malinali-app/traduction-wolof-en':
            return 'How are you';
          case 'Xenova/opus-mt-en-fr':
            return 'Comment allez-vous';
        }
        throw StateError('unexpected model ${model.modelId}');
      },
    ).run(wavPath: 'nanga_def.wav', plan: plan);

    expect(plan.strategy, VoiceSpeechStrategy.transcribeThenMarianToEnglish);
    expect(plan.whisperLanguage, 'en');
    expect(plan.translateToEnglish, isFalse);
    expect(whisper.language, 'en');
    expect(whisper.translate, isFalse);
    expect(whisper.pack?.id, 'wolof-small');
    expect(seen['malinali-app/traduction-wolof-en'], 'Nanga def');
    expect(seen['Xenova/opus-mt-en-fr'], 'How are you');
    expect(turn.sourceTranscript, 'Nanga def');
    expect(turn.englishText, 'How are you');
    expect(turn.targetText, 'Comment allez-vous');
  });
}
