import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:malinali/pages/translate_page.dart';
import 'package:malinali/pages/settings_page.dart';
import 'package:malinali/pages/translation_settings_page.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/services/speech_recognition_service.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:marian_flutter/marian_flutter.dart';

import 'translate_page_test.mocks.dart';

class FakeSpeechRecognitionService extends Fake
    implements SpeechRecognitionService {
  bool _initialized = false;
  bool _listening = false;
  int startCount = 0;
  int stopCount = 0;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isListening => _listening;

  @override
  VoskModel? get currentModel => VoskModelService.assetFrenchModel;

  @override
  Function(String)? onResult;

  @override
  Function(String)? onPartialResult;

  @override
  Function()? onError;

  @override
  Future<void> initialize({VoskModel? model}) async {
    _initialized = true;
  }

  @override
  Future<void> switchModel(VoskModel model) async {}

  @override
  Future<void> startListening() async {
    _listening = true;
    startCount++;
  }

  @override
  Future<void> stopListening() async {
    _listening = false;
    stopCount++;
  }

  @override
  void dispose() {
    _listening = false;
  }
}

@GenerateMocks([TranslationModelService, MarianService])
void main() {
  late MockTranslationModelService mockModelService;
  late MockMarianService mockMarian;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    mockModelService = MockTranslationModelService();
    mockMarian = MockMarianService();
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return '.';
      }
      return null;
    });
  });

  testWidgets('TranslatePage language pair selector is clickable and opens TranslationSettingsPage', (WidgetTester tester) async {
    final model = TranslationModel(
      sourceLang: Languages.french,
      targetLang: Languages.english,
      modelId: 'opus-mt-fr-en',
    );

    when(mockModelService.fetchAvailableModels(any)).thenAnswer((_) async => []);
    when(mockModelService.fetchAllAvailableModels()).thenAnswer((_) async => [model]);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: TranslatePage(
          initialMarian: mockMarian,
          modelService: mockModelService,
        ),
      ));
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    });

    // Find the header text "Français → Pulaar" (default)
    expect(find.textContaining('Français → Pulaar'), findsOneWidget);

    // Click the language pair selector
    await tester.tap(find.textContaining('Français → Pulaar'));
    await tester.pump(); // Start navigation
    await tester.pump(const Duration(milliseconds: 500)); // Animation
    await tester.pump(); // Finish navigation

    // Should now be on TranslationSettingsPage
    expect(find.byType(TranslationSettingsPage), findsOneWidget);
    expect(find.text('Modèles de traduction'), findsOneWidget);
  });

  testWidgets('TranslatePage settings button opens SettingsPage', (WidgetTester tester) async {
    when(mockModelService.fetchAvailableModels(any)).thenAnswer((_) async => []);
    when(mockModelService.fetchAllAvailableModels()).thenAnswer((_) async => []);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: TranslatePage(
          initialMarian: mockMarian,
          modelService: mockModelService,
        ),
      ));
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    });

    // Find settings button in top right
    final settingsButton = find.byTooltip('Paramètres');
    expect(settingsButton, findsOneWidget);

    // Click the settings button
    await tester.tap(settingsButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // Should now be on SettingsPage
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Paramètres'), findsOneWidget);
  });

  testWidgets('TranslatePage displays mic button when source has VOSK model', (WidgetTester tester) async {
    when(mockModelService.fetchAvailableModels(any)).thenAnswer((_) async => []);
    when(mockModelService.fetchAllAvailableModels()).thenAnswer((_) async => []);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: TranslatePage(
          initialMarian: mockMarian,
          modelService: mockModelService,
        ),
      ));
      await Future.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });

    // Default source is French, which has asset VOSK model
    // Mic icon should be visible in input area
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    // Header should also display mic icon for matching Vosk model
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });

  testWidgets(
      'Clicking mic toggles listening ON, and clicking again stops listening cleanly',
      (WidgetTester tester) async {
    final fakeSpeech = FakeSpeechRecognitionService();

    when(mockModelService.fetchAvailableModels(any))
        .thenAnswer((_) async => []);
    when(mockModelService.fetchAllAvailableModels())
        .thenAnswer((_) async => []);
    when(mockMarian.translate(any, config: anyNamed('config')))
        .thenAnswer((_) async => 'Hello world');

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: TranslatePage(
          initialMarian: mockMarian,
          modelService: mockModelService,
          speechService: fakeSpeech,
        ),
      ));
      await Future.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });

    // 1. Initial state: idle, mic_none visible
    expect(fakeSpeech.isListening, isFalse);
    expect(fakeSpeech.startCount, 0);
    expect(fakeSpeech.stopCount, 0);

    final micButton = find.byIcon(Icons.mic_none);
    expect(micButton, findsOneWidget);

    // 2. First click: Starts recording
    await tester.tap(micButton);
    await tester.pump();

    expect(fakeSpeech.isListening, isTrue);
    expect(fakeSpeech.startCount, 1);
    expect(fakeSpeech.stopCount, 0);

    // 3. While recording, mic icon is active (Icons.mic)
    // One Icons.mic in header status, one in recording button
    expect(find.byIcon(Icons.mic), findsNWidgets(2));
    expect(find.byIcon(Icons.mic_none), findsNothing);

    // Simulate Vosk intermediate utterance
    fakeSpeech.onResult?.call('Bonjour');
    await tester.pump();

    // Intermediate speech does NOT stop recording; mic stays active
    expect(fakeSpeech.isListening, isTrue);
    expect(fakeSpeech.stopCount, 0);

    // 4. Second click on active mic: Finishes recording and stops listening
    // We tap the input button (which is currently Icons.mic)
    final activeMicButtons = find.byIcon(Icons.mic);
    // The last one is the one inside the input card
    await tester.tap(activeMicButtons.last);
    await tester.pump();

    // 5. Must be completely stopped
    expect(fakeSpeech.isListening, isFalse);
    expect(fakeSpeech.stopCount, 1);

    // Mic icon returns to idle
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });
}
