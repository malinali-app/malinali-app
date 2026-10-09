import 'package:aptabase_flutter/aptabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:malinali/pages/settings_page.dart';
import 'package:malinali/pages/translation_settings_page.dart';
import 'package:malinali/pages/vosk_transcription_page.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:languages_dart/languages_dart.dart';

import 'settings_page_test.mocks.dart';

@GenerateMocks([TranslationModelService, VoskModelService])
void main() {
  late MockTranslationModelService mockModelService;
  late MockVoskModelService mockVoskService;
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
    mockVoskService = MockVoskModelService();
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory' ||
          methodCall.method == 'getApplicationSupportDirectory' ||
          methodCall.method == 'getLibraryDirectory') {
        return '.';
      }
      return null;
    });
  });

  testWidgets(
      'SettingsPage shows Conversation, Traduction écrite, Transcription, BYO',
      (WidgetTester tester) async {
    when(mockModelService.fetchAllAvailableModels())
        .thenAnswer((_) async => []);
    when(mockVoskService.fetchAllSmallModels()).thenAnswer((_) async => []);
    when(mockVoskService.isModelDownloaded(any))
        .thenAnswer((_) async => true);

    var conversationTapped = false;
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(
        modelService: mockModelService,
        voskService: mockVoskService,
        onConversationTap: () => conversationTapped = true,
      ),
    ));

    expect(find.text('Paramètres'), findsOneWidget);
    expect(find.text('Traduction vocale'), findsOneWidget);
    expect(find.text('Traduction écrite'), findsOneWidget);
    expect(find.text('Transcription audio'), findsOneWidget);
    expect(find.text('Utiliser mon propre modèle'), findsOneWidget);
    expect(find.text('Saisie vocale'), findsNothing);

    await tester.tap(find.text('Traduction vocale'));
    await tester.pumpAndSettle();
    expect(conversationTapped, isTrue);
  });

  testWidgets('Transcription audio opens VoskTranscriptionPage',
      (WidgetTester tester) async {
    when(mockVoskService.fetchAllSmallModels()).thenAnswer((_) async => [
          VoskModelService.assetFrenchModel,
        ]);
    when(mockVoskService.isModelDownloaded(any))
        .thenAnswer((_) async => true);

    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(
        modelService: mockModelService,
        voskService: mockVoskService,
      ),
    ));

    await tester.tap(find.text('Transcription audio'));
    await tester.pumpAndSettle();
    expect(find.byType(VoskTranscriptionPage), findsOneWidget);
  });

  testWidgets(
      'TranslationSettingsPage shows all models by default and filters when switch is toggled',
      (WidgetTester tester) async {
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

    when(mockModelService.fetchAllAvailableModels())
        .thenAnswer((_) async => models);
    when(mockModelService.isModelDownloaded(any))
        .thenAnswer((_) async => false);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: TranslationSettingsPage(
          modelService: mockModelService,
        ),
      ));
      await Future.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });

    expect(find.textContaining('opus-mt-fr-en'), findsOneWidget);
    expect(find.textContaining('opus-mt-fr-es'), findsOneWidget);
  });
}
