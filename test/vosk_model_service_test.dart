import 'package:flutter_test/flutter_test.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/services/vosk_model_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VoskModelService voskService;

  setUp(() {
    voskService = VoskModelService();
  });

  group('VoskModelService', () {
    test('Curated small models contains official small models and asset French model', () {
      final models = VoskModelService.curatedSmallModels;
      expect(models, isNotEmpty);
      expect(models.any((m) => m.name == 'vosk-model-small-fr-0.22'), isTrue);
      expect(models.any((m) => m.name == 'vosk-model-small-en-us-0.15'), isTrue);
      expect(models.any((m) => m.name == 'vosk-model-small-es-0.42'), isTrue);
      expect(models.any((m) => m.name == 'vosk-model-small-de-0.15'), isTrue);

      final fr = models.firstWhere((m) => m.name == 'vosk-model-small-fr-0.22');
      expect(fr.isAsset, isTrue);
      expect(fr.assetPath, 'assets/vosk-model-small-fr-0.22.zip');
    });

    test('findModelForLanguage matches French to asset model', () {
      final model = voskService.findModelForLanguage(
        Languages.french,
        VoskModelService.curatedSmallModels,
      );
      expect(model, isNotNull);
      expect(model!.name, 'vosk-model-small-fr-0.22');
      expect(model.isAsset, isTrue);
    });

    test('findModelForLanguage matches English to US English model', () {
      final model = voskService.findModelForLanguage(
        Languages.english,
        VoskModelService.curatedSmallModels,
      );
      expect(model, isNotNull);
      expect(model!.name, 'vosk-model-small-en-us-0.15');
      expect(model.isAsset, isFalse);
    });

    test('findModelForLanguage matches Spanish to Spanish model', () {
      final model = voskService.findModelForLanguage(
        Languages.spanish,
        VoskModelService.curatedSmallModels,
      );
      expect(model, isNotNull);
      expect(model!.lang, 'es');
    });

    test('findModelForLanguage matches German to German model', () {
      final model = voskService.findModelForLanguage(
        Languages.german,
        VoskModelService.curatedSmallModels,
      );
      expect(model, isNotNull);
      expect(model!.lang, 'de');
    });

    test('findModelForLanguage returns null for unsupported local dialects like Fula without VOSK model', () {
      final model = voskService.findModelForLanguage(
        Languages.fulah,
        VoskModelService.curatedSmallModels,
      );
      expect(model, isNull);
    });

    test('asset French model is always considered downloaded', () async {
      final isDownloaded = await voskService.isModelDownloaded(
        VoskModelService.assetFrenchModel,
      );
      expect(isDownloaded, isTrue);
    });
  });
}
