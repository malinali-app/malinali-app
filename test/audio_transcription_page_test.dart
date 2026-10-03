import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/pages/audio_transcription_page.dart';
import 'package:malinali/services/vosk_model_service.dart';

void main() {
  testWidgets(
    'Traduire pops transcript for the current language pair',
    (tester) async {
      String? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      popped = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AudioTranscriptionPage(
                            voskService: VoskModelService(),
                            initialTranscript: 'Bonjour le monde',
                            translationPairLabel: 'Français → Pulaar',
                          ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Bonjour le monde'), findsOneWidget);
      expect(find.text('Traduire (Français → Pulaar)'), findsOneWidget);

      await tester.tap(find.text('Traduire (Français → Pulaar)'));
      await tester.pumpAndSettle();

      expect(popped, 'Bonjour le monde');
    },
  );
}
