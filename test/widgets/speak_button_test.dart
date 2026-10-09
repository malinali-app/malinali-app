import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:malinali/pages/translate_page.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:marian_flutter/marian_flutter.dart';

import '../translate_page_test.mocks.dart';

void main() {
  late MockTranslationModelService mockModelService;
  late MockMarianService mockMarian;
  bool aptabaseInitialized = false;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    if (!aptabaseInitialized) {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'Malinali',
        packageName: 'com.malinali.app',
        version: '1.1.6',
        buildNumber: '116',
        buildSignature: '',
      );
      await Aptabase.init('A-DEV-0000000000');
      aptabaseInitialized = true;
    }
    mockModelService = MockTranslationModelService();
    mockMarian = MockMarianService();
    
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return '.';
      }
      return null;
    });
    
    // Mock the flutter_tts channel
    const MethodChannel('flutter_tts')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'isLanguageAvailable') {
        return true;
      }
      return 1;
    });
  });

  testWidgets('Speak button appears when there is translation output', (WidgetTester tester) async {
    final model = TranslationModel(
      sourceLang: Languages.french,
      targetLang: Languages.english,
      modelId: 'opus-mt-fr-en',
    );

    when(mockModelService.fetchAvailableModels(any)).thenAnswer((_) async => []);
    when(mockModelService.fetchAllAvailableModels()).thenAnswer((_) async => [model]);
    when(mockModelService.isModelDownloaded(any)).thenAnswer((_) async => true);
    when(mockMarian.translate(any, config: anyNamed('config')))
        .thenAnswer((_) async => 'Hello world');

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: TranslatePage(
          initialMarian: mockMarian,
          initialModel: model,
          modelService: mockModelService,
        ),
      ));
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    });

    // Enter some text
    await tester.enterText(find.byType(TextField), 'Bonjour');
    await tester.pump();

    // Click translate button
    await tester.tap(find.text('Traduire'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // Animation

    // Output should be displayed
    expect(find.text('Hello world'), findsOneWidget);

    // Speak button should be visible
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    
    // Tapping speak button
    await tester.tap(find.byIcon(Icons.volume_up_rounded));
    await tester.pump();
    
    // No error occurred
    expect(tester.takeException(), isNull);
  });
}
