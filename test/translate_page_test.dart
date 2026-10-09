import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:malinali/pages/translate_page.dart';
import 'package:malinali/pages/translation_settings_page.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:marian_flutter/marian_flutter.dart';

import 'translate_page_test.mocks.dart';

@GenerateMocks([TranslationModelService, MarianService])
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
  });

  testWidgets(
      'TranslatePage language pair selector opens TranslationSettingsPage',
      (WidgetTester tester) async {
    final model = TranslationModel(
      sourceLang: Languages.french,
      targetLang: Languages.english,
      modelId: 'opus-mt-fr-en',
    );

    when(mockModelService.fetchAvailableModels(any))
        .thenAnswer((_) async => []);
    when(mockModelService.fetchAllAvailableModels())
        .thenAnswer((_) async => [model]);
    when(mockModelService.isModelDownloaded(any))
        .thenAnswer((_) async => false);

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

    expect(find.textContaining('Français → English'), findsOneWidget);

    await tester.tap(find.textContaining('Français → English'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.byType(TranslationSettingsPage), findsOneWidget);
  });

  testWidgets('TranslatePage settings opens TranslationSettingsPage',
      (WidgetTester tester) async {
    when(mockModelService.fetchAvailableModels(any))
        .thenAnswer((_) async => []);
    when(mockModelService.fetchAllAvailableModels())
        .thenAnswer((_) async => []);
    when(mockModelService.isModelDownloaded(any))
        .thenAnswer((_) async => false);

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

    final settingsButton = find.byTooltip('Paramètres');
    expect(settingsButton, findsOneWidget);

    await tester.tap(settingsButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.byType(TranslationSettingsPage), findsOneWidget);
  });

  testWidgets('TranslatePage has no microphone UI', (WidgetTester tester) async {
    when(mockModelService.fetchAvailableModels(any))
        .thenAnswer((_) async => []);
    when(mockModelService.fetchAllAvailableModels())
        .thenAnswer((_) async => []);
    when(mockModelService.isModelDownloaded(any))
        .thenAnswer((_) async => false);

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

    expect(find.byIcon(Icons.mic_none), findsNothing);
    expect(find.byIcon(Icons.mic), findsNothing);
  });
}
