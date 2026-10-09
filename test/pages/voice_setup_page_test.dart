import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/pages/voice_setup_page.dart';
import 'package:malinali/services/voice_preferences.dart';

class _MemoryStore extends VoicePreferencesStore {
  VoicePreferences? saved;

  @override
  Future<VoicePreferences?> load() async => saved;

  @override
  Future<void> save(VoicePreferences prefs) async {
    saved = prefs;
  }

  @override
  Future<bool> hasCompletedSetup() async => saved != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return '.';
      }
      return null;
    });
  });

  testWidgets('first run defaults to Wolof, French, 250 Mo', (tester) async {
    final store = _MemoryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  final result = await Navigator.push<VoicePreferences>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VoiceSetupPage(store: store),
                    ),
                  );
                  store.saved = result;
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Traduction vocale'), findsOneWidget);

    final sizeHint = find.text('environ 250 Mo');
    await tester.scrollUntilVisible(sizeHint, 300);
    await tester.pumpAndSettle();
    expect(sizeHint, findsOneWidget);
    expect(find.text('environ 75 Mo'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Continuer'), 200);
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    expect(store.saved?.sourceIso, 'wo');
    expect(store.saved?.targetIso, 'fr');
    expect(store.saved?.whisperSize, VoiceWhisperSize.quality);
  });
}
