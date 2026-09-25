import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:malinali/pages/settings_page.dart';
import 'package:malinali/pages/translation_settings_page.dart';
import 'package:malinali/pages/transcription_settings_page.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:languages_dart/languages_dart.dart';

import 'settings_page_test.mocks.dart';

@GenerateMocks([TranslationModelService])
void main() {
  late MockTranslationModelService mockModelService;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    mockModelService = MockTranslationModelService();
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return '.';
      }
      return null;
    });
  });

  testWidgets('SettingsPage shows two tiles: Traduction and Transcription', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(modelService: mockModelService),
    ));

    expect(find.text('Paramètres'), findsOneWidget);
    expect(find.text('Traduction'), findsOneWidget);
    expect(find.text('Transcription'), findsOneWidget);

    expect(find.byIcon(Icons.translate), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);

    // Tap Traduction tile -> opens TranslationSettingsPage
    await tester.tap(find.text('Traduction'));
    await tester.pumpAndSettle();
    expect(find.byType(TranslationSettingsPage), findsOneWidget);

    // Go back to SettingsPage
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    // Tap Transcription tile -> opens TranscriptionSettingsPage
    await tester.tap(find.text('Transcription'));
    await tester.pumpAndSettle();
    expect(find.byType(TranscriptionSettingsPage), findsOneWidget);
  });

  testWidgets('TranslationSettingsPage shows all models by default and filters when switch is toggled', (WidgetTester tester) async {
    final models = [
      TranslationModel(
        sourceLang: Languages.french,
        targetLang: Languages.english,
        modelId: 'opus-mt-fr-en',
      ),
      TranslationModel(
        sourceLang: Languages.french,
        targetLang: Languages.spanish,
        modelId: 'opus-mt-fr-es',
      ),
    ];

    when(mockModelService.fetchAllAvailableModels()).thenAnswer((_) async => models);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: TranslationSettingsPage(modelService: mockModelService),
      ));

      // Wait for models to load
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    // Check for errors
    if (find.byType(SnackBar).evaluate().isNotEmpty) {
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      final text = (snackBar.content as Text).data;
      fail('Error loading models: $text');
    }

    // Verify both models are shown by default
    expect(find.byType(ListTile), findsNWidgets(2));

    // Toggle the switch
    final switchFinder = find.byType(Switch);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Since neither is downloaded, both should be filtered out
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Aucun modèle trouvé'), findsOneWidget);

    // Toggle back
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Both should be back
    expect(find.byType(ListTile), findsNWidgets(2));

    // Switch to Target search mode
    final targetChip = find.text('Cible');
    await tester.tap(targetChip);
    await tester.pumpAndSettle();

    // Search for a model when switch is OFF
    final textField = find.byType(TextField);
    await tester.enterText(textField, 'English');
    await tester.pumpAndSettle();

    // Should find the English model
    expect(find.textContaining('French → English'), findsOneWidget);
    expect(find.textContaining('French → Spanish'), findsNothing);

    // Toggle switch ON while searching
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Should find nothing since it's not downloaded
    expect(find.textContaining('French → English'), findsNothing);
    expect(find.text('Aucun modèle trouvé'), findsOneWidget);

    // Clear search and toggle switch OFF
    await tester.enterText(textField, '');
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(2));
  });
}
