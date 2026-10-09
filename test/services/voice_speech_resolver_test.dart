import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/voice_speech_resolver.dart';

void main() {
  const resolver = VoiceSpeechResolver();

  test('defaults are Wolof → French with 250 Mo size', () {
    expect(VoicePreferences.defaults.sourceIso, 'wo');
    expect(VoicePreferences.defaults.targetIso, 'fr');
    expect(VoicePreferences.defaults.whisperSize, VoiceWhisperSize.quality);
  });

  test('Wolof to French uses wolof-small then wo→en then en→fr', () {
    final plan = resolver.resolve(VoicePreferences.defaults);
    expect(plan.strategy, VoiceSpeechStrategy.transcribeThenMarianToEnglish);
    expect(plan.specialist?.id, 'wolof-small');
    expect(plan.whisperLanguage, 'en');
    expect(plan.translateToEnglish, isFalse);
    expect(plan.sourceToEnglish?.modelId, 'malinali-app/traduction-wolof-en');
    expect(plan.englishToTarget?.modelId, 'Xenova/opus-mt-en-fr');
    expect(plan.genericModel.modelName, 'small');
  });

  test('Yoruba to French uses the direct model and the Yoruba fine-tune', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'yo',
        targetIso: 'fr',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    expect(plan.strategy, VoiceSpeechStrategy.directTranslate);
    expect(plan.specialist?.id, 'yoruba-small');
    expect(plan.whisperLanguage, 'yo');
    expect(plan.sourceToEnglish?.modelId, 'malinali-app/opus-mt-yo-fr');
    expect(plan.englishToTarget, isNull);
    expect(plan.translateToEnglish, isFalse);
  });

  test('Swahili resolves to generic translate (no sw→en Marian)', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'sw',
        targetIso: 'fr',
        whisperSize: VoiceWhisperSize.compact,
      ),
    );
    expect(plan.strategy, VoiceSpeechStrategy.genericTranslate);
    expect(plan.specialist, isNull);
    expect(plan.whisperLanguage, 'sw');
    expect(plan.genericModel.modelName, 'tiny');
  });

  test('Wolof to English transcribes then uses the direct wo→en model', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'wo',
        targetIso: 'en',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    expect(plan.strategy, VoiceSpeechStrategy.directTranslate);
    expect(plan.specialist?.id, 'wolof-small');
    expect(plan.whisperLanguage, 'en');
    expect(plan.sourceToEnglish?.modelId, 'malinali-app/traduction-wolof-en');
    expect(plan.englishToTarget, isNull);
    expect(plan.marianDownloads.map((m) => m.modelId), [
      'malinali-app/traduction-wolof-en',
    ]);
  });

  test('Kinyarwanda fine-tune is gated so cascade is not offered', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'rw',
        targetIso: 'fr',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    // No downloadable Whisper pack. A direct rw→fr Marian model still applies.
    expect(plan.strategy, VoiceSpeechStrategy.directTranslate);
    expect(plan.specialist, isNull);
    expect(plan.sourceToEnglish?.modelId, 'malinali-app/opus-mt-rw-fr');
  });

  test('spoken language list is downloadable packs only', () {
    final packs = voiceSpokenLanguagePacks();
    expect(packs.map((p) => p.id), [
      'generic-en',
      'generic-fr',
      'swahili-small',
      'yoruba-small',
      'wolof-small',
    ]);
  });

  test('pinned en→fr is first among voice English targets', () {
    final targets = voiceEnglishTargetModels();
    expect(targets.first.modelId, 'Xenova/opus-mt-en-fr');
    expect(
      targets.any((m) => m.modelId == 'malinali-app/traduction-en-wolof'),
      isTrue,
    );
  });

  test('Wolof target uses English→Wolof candle fine-tune', () {
    final plan = resolver.resolve(
      const VoicePreferences(
        sourceIso: 'yo',
        targetIso: 'wo',
        whisperSize: VoiceWhisperSize.quality,
      ),
    );
    expect(plan.englishToTarget?.modelId, 'malinali-app/traduction-en-wolof');
    expect(
      plan.englishToTarget?.sourcePrefix,
      TranslationModelService.kEngWolofSourcePrefix,
    );
  });
}
