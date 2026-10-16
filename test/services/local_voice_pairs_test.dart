import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/local_voice_pairs.dart';
import 'package:malinali/services/voice_preferences.dart';

void main() {
  test('readyVoicePairs keeps only pairs whose models are on disk', () async {
    const prefs = VoicePreferences(
      sourceIso: 'fr',
      targetIso: 'en',
      whisperSize: VoiceWhisperSize.quality,
      useFastSttForEnFr: false,
    );

    final pairs = await readyVoicePairs(
      prefs: prefs,
      modelsReady: (plan) async {
        return plan.sourceIso == 'fr' &&
            plan.translateToEnglish &&
            plan.marianDownloads.isEmpty;
      },
    );

    expect(pairs, hasLength(1));
    expect(pairs.single.sourceIso, 'fr');
    expect(pairs.single.targetIso, 'en');
  });
}
