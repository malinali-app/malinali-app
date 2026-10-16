import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/pages/voice_chat_page.dart';
import 'package:malinali/services/tts_service.dart';
import 'package:malinali/services/voice_turn_pipeline.dart';

class _FakeTts extends Fake implements TtsService {
  _FakeTts({this.wellSupported = const {}});

  final Set<String> wellSupported;

  @override
  bool isLanguageWellSupported(String iso) =>
      wellSupported.contains(iso.toLowerCase());
}

void main() {
  testWidgets(
    'source bubble shows the transcript and play reports a missing file',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceTurnBubbles(
              turn: const VoiceTurn(
                wavPath: 'missing-note.wav',
                sourceTranscript: 'Na nga def',
                targetText: 'Bonjour',
              ),
              sourceIso: 'wo',
              targetIso: 'fr',
              tts: _FakeTts(),
              ttsAvailable: false,
            ),
          ),
        ),
      );

      expect(find.text('Na nga def'), findsOneWidget);
      expect(find.text('Bonjour'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Lecture impossible'), findsOneWidget);
    },
  );

  testWidgets('hides the left bubble while translation is still running', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceTurnBubbles(
            turn: const VoiceTurn(
              wavPath: 'note.wav',
              sourceTranscript: 'hello there',
              targetText: '',
              isTranslating: true,
            ),
            sourceIso: 'en',
            targetIso: 'fr',
            tts: _FakeTts(),
            ttsAvailable: false,
          ),
        ),
      ),
    );

    expect(find.text('hello there'), findsOneWidget);
    expect(find.text('Traduction…'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('shows the speaker on a Wolof translation bubble', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceTurnBubbles(
            turn: const VoiceTurn(
              wavPath: 'note.wav',
              sourceTranscript: 'Bonjour',
              targetText: 'Nanga def',
            ),
            sourceIso: 'fr',
            targetIso: 'wo',
            tts: _FakeTts(wellSupported: {'wo'}),
            ttsAvailable: true,
          ),
        ),
      ),
    );

    expect(find.text('Nanga def'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
  });
}
