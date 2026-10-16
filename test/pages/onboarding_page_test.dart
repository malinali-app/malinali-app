import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/pages/onboarding_page.dart';
import 'package:malinali/services/voice_preferences.dart';
import 'package:malinali/services/voice_speech_resolver.dart';
import 'package:malinali/services/voice_turn_pipeline.dart';
import 'package:malinali/services/whisper_speech_service.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:mockito/mockito.dart';

class _MockStore extends VoicePreferencesStore {
  VoicePreferences? saved;

  @override
  Future<VoicePreferences?> load() async => saved;

  @override
  Future<void> save(VoicePreferences prefs) async {
    saved = prefs;
  }
}

class _FakePipeline extends Fake implements VoiceTurnPipeline {
  _FakePipeline({this.isReady = true, this.throwOnEnsure = false});

  final bool isReady;
  final bool throwOnEnsure;
  bool ensureCalled = false;

  @override
  Future<bool> modelsReady(VoiceSpeechPlan plan) async {
    return isReady;
  }

  @override
  Future<void> ensureModels(
    VoiceSpeechPlan plan, {
    void Function(String status)? onStatus,
    void Function(double? progress)? onProgress,
  }) async {
    ensureCalled = true;
    onProgress?.call(0.5);
    if (throwOnEnsure) {
      throw Exception('Network error');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.isEnabled',
    ]) {
      messenger.setMockMessageHandler(name, (_) async => null);
    }
  });
  testWidgets('Screen 1 shows English and Français only (no Wolof source)', (tester) async {
    final store = _MockStore();
    final pipeline = _FakePipeline(isReady: true);

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingFlow(
          store: store,
          pipeline: pipeline,
        ),
      ),
    );

    // Header elements
    expect(find.text('Malinali'), findsOneWidget);
    expect(find.text('Choisissez votre langue'), findsOneWidget);

    expect(find.text('English'), findsOneWidget);
    expect(find.text('Français'), findsOneWidget);
    // Wolof is a target only, not a spoken source.
    expect(find.text('Wolof'), findsNothing);

    // Country flags should NOT be present
    expect(find.text('🇫🇷'), findsNothing);
    expect(find.text('🇺🇸'), findsNothing);
    expect(find.text('🇸🇳'), findsNothing);
  });

  testWidgets('French source shows English, Wolof, and African languages with BLEU >= 30', (tester) async {
    final store = _MockStore();
    final pipeline = _FakePipeline(isReady: true);

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingFlow(
          store: store,
          pipeline: pipeline,
        ),
      ),
    );

    // Select Français
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    expect(find.text('Langue de traduction'), findsOneWidget);

    // English reciprocal, Wolof, and Lingala (BLEU 30.5)
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Wolof'), findsOneWidget);
    expect(find.text('Lingála'), findsOneWidget);

    // Hausa (BLEU 24.4) or Swahili (BLEU 28.2) should NOT be displayed
    expect(find.text('Hausa'), findsNothing);
    expect(find.text('Congo Swahili'), findsNothing);
  });

  testWidgets('English source shows French, Wolof, and African languages with BLEU >= 30', (tester) async {
    final store = _MockStore();
    final pipeline = _FakePipeline(isReady: true);

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingFlow(
          store: store,
          pipeline: pipeline,
        ),
      ),
    );

    // Select English
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Langue de traduction'), findsOneWidget);

    // French reciprocal, Wolof, and BLEU >= 30 languages
    expect(find.text('Français'), findsOneWidget);
    expect(find.text('Wolof'), findsOneWidget);
    expect(find.text('Igbo'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Twi'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Twi'), findsOneWidget);

    // Rundi (BLEU 10.4) should NOT be displayed
    expect(find.text('Ikirundi'), findsNothing);
  });

  testWidgets('If model is already ready, completing onboarding pops and saves preferences', (tester) async {
    final store = _MockStore();
    final pipeline = _FakePipeline(isReady: true);

    VoicePreferences? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await Navigator.push<VoicePreferences>(
                context,
                MaterialPageRoute(
                  builder: (_) => OnboardingFlow(
                    store: store,
                    pipeline: pipeline,
                  ),
                ),
              );
            },
            child: const Text('launch'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();

    // Select Français as source, Wolof as target
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wolof'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    // Model was ready, so it should finish and pop
    expect(popped, isNotNull);
    expect(popped!.sourceIso, 'fr');
    expect(popped!.targetIso, 'wo');
    expect(store.saved?.sourceIso, 'fr');
    expect(store.saved?.targetIso, 'wo');
    expect(store.saved?.useFastSttForEnFr, isTrue);
  });

  testWidgets('does not leave onboarding when models are still missing', (
    tester,
  ) async {
    final store = _MockStore();
    final pipeline = _FakePipeline(isReady: false);

    VoicePreferences? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await Navigator.push<VoicePreferences>(
                context,
                MaterialPageRoute(
                  builder: (_) => OnboardingFlow(
                    store: store,
                    pipeline: pipeline,
                    isOnline: () async => true,
                  ),
                ),
              );
            },
            child: const Text('launch'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('launch'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Wolof'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Wolof'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(popped, isNull);
    expect(find.text('launch'), findsNothing);
    expect(store.saved, isNull);
    expect(pipeline.ensureCalled, isTrue);
    expect(find.text('Erreur de téléchargement'), findsOneWidget);
    expect(
      find.text('Les modèles de cette paire ne sont pas prêts.'),
      findsOneWidget,
    );
    expect(pipeline.ensureCalled, isTrue);
  });

  testWidgets('Target step uses SingleChildScrollView and keeps Continuer button clickable', (tester) async {
    final store = _MockStore();
    final pipeline = _FakePipeline(isReady: true);

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingFlow(
          store: store,
          pipeline: pipeline,
        ),
      ),
    );

    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    // Verify SingleChildScrollView is present
    expect(find.byType(SingleChildScrollView), findsAtLeastNWidgets(1));

    // Bottom Continuer button is visible and enabled
    final continuerBtn = find.widgetWithText(FilledButton, 'Continuer');
    expect(continuerBtn, findsOneWidget);
    final button = tester.widget<FilledButton>(continuerBtn);
    expect(button.onPressed, isNotNull);
  });
}
