import 'package:flutter_test/flutter_test.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/services/translation_model_service.dart';

void main() {
  group('TranslationModelService Audit and Filtering', () {
    test('Rejects models without tokenizer.json and without Xenova fallback (like tonythethompson/Opus-MT-En-PT)', () {
      final service = TranslationModelService();
      final models = <TranslationModel>[];

      final fakeHFData = [
        // 1. Problematic model: no tokenizer.json, base_model tc-big, 232M params
        {
          'id': 'tonythethompson/Opus-MT-En-PT',
          'siblings': [
            {'rfilename': 'model.safetensors'},
            {'rfilename': 'source.spm'},
            {'rfilename': 'target.spm'},
            {'rfilename': 'vocab.json'},
          ],
          'cardData': {
            'base_model': 'Helsinki-NLP/opus-mt-tc-big-en-pt',
          },
          'safetensors': {
            'total': 232502776,
          },
        },
        // 2. Problematic model: missing model.safetensors
        {
          'id': 'random/opus-mt-fr-es',
          'siblings': [
            {'rfilename': 'pytorch_model.bin'},
            {'rfilename': 'tokenizer.json'},
          ],
        },
        // 3. Valid model: has model.safetensors and tokenizer.json
        {
          'id': 'Xenova/opus-mt-en-fr',
          'siblings': [
            {'rfilename': 'model.safetensors'},
            {'rfilename': 'tokenizer.json'},
            {'rfilename': 'config.json'},
          ],
          'safetensors': {
            'total': 74000000,
          },
        },
      ];

      service.parseAndAddModelsForTesting(
        fakeHFData,
        models,
        safeNames: {'opus-mt-en-fr'},
      );

      // tonythethompson/Opus-MT-En-PT and pytorch-only models must be rejected
      expect(models.any((m) => m.modelId == 'tonythethompson/Opus-MT-En-PT'), isFalse);
      expect(models.any((m) => m.modelId == 'random/opus-mt-fr-es'), isFalse);

      // Valid model must be accepted
      expect(models.any((m) => m.modelId == 'Xenova/opus-mt-en-fr'), isTrue);
      expect(models.length, 1);
    });

    test('Rejects tc-big models even if safetensors exists', () {
      final service = TranslationModelService();
      final models = <TranslationModel>[];

      final bigModel = [
        {
          'id': 'Helsinki-NLP/opus-mt-tc-big-fr-en',
          'siblings': [
            {'rfilename': 'model.safetensors'},
            {'rfilename': 'tokenizer.json'},
          ],
          'safetensors': {
            'total': 232000000,
          },
        }
      ];

      service.parseAndAddModelsForTesting(bigModel, models);
      expect(models, isEmpty);
    });

    test('Accepts Xenova models without model.safetensors in their own repo siblings', () {
      final service = TranslationModelService();
      final models = <TranslationModel>[];

      final xenovaModel = [
        {
          'id': 'Xenova/opus-mt-fr-es',
          'siblings': [
            {'rfilename': 'config.json'},
            {'rfilename': 'tokenizer.json'},
            {'rfilename': 'onnx/encoder_model.onnx'},
          ],
        }
      ];

      service.parseAndAddModelsForTesting(xenovaModel, models);
      expect(models.length, 1);
      expect(models.first.modelId, 'Xenova/opus-mt-fr-es');
      expect(models.first.sourceLang.name, 'Français');
    });

    test('dedupeByLanguagePair keeps a single fr→en preferring Xenova', () {
      final service = TranslationModelService();
      final models = [
        TranslationModel(
          sourceLang: Languages.french,
          targetLang: Languages.english,
          modelId: 'Helsinki-NLP/opus-mt-fr-en',
        ),
        TranslationModel(
          sourceLang: Languages.french,
          targetLang: Languages.english,
          modelId: 'Xenova/opus-mt-fr-en',
        ),
        TranslationModel(
          sourceLang: Languages.french,
          targetLang: Languages.spanish,
          modelId: 'Xenova/opus-mt-fr-es',
        ),
      ];
      final deduped = service.dedupeByLanguagePair(models);
      expect(deduped.length, 2);
      final frEn = deduped.where((m) => m.pairKey == 'fr|en').toList();
      expect(frEn.length, 1);
      expect(frEn.first.modelId, 'Xenova/opus-mt-fr-en');
    });

    test('private Fula model is HF on-demand, not an asset', () {
      final fula = TranslationModelService.privateModels.first;
      expect(fula.modelId, 'flutter-painter/french-fula');
      expect(fula.isAsset, isFalse);
      expect(fula.requiresAuth, isTrue);
      expect(fula.downloadSizeHint, '~285 Mo');
    });

    test('boot default is public tiny Helsinki FR→EN', () {
      final boot = TranslationModelService.defaultBootModel;
      expect(boot.modelId, 'Helsinki-NLP/opus-mt_tiny_fra-eng');
      expect(boot.isAsset, isFalse);
      expect(boot.requiresAuth, isFalse);
    });

    test('curated African Helsinki bilaterals include Hausa/Yoruba with BLEU hints', () {
      final service = TranslationModelService();
      final african = service.debugCuratedAfricanModels();
      expect(african.length, greaterThan(40));
      expect(
        african.any((m) => m.modelId == 'malinali-app/opus-mt-en-ha'),
        isTrue,
      );
      expect(
        african.any((m) => m.modelId == 'malinali-app/opus-mt-yo-en'),
        isTrue,
      );
      final ha = african.firstWhere((m) => m.modelId == 'malinali-app/opus-mt-en-ha');
      expect(ha.qualityHint, 'BLEU 34.1 / 100');
      // Multilingual packs must stay out of the curated bilateral list.
      expect(african.any((m) => m.modelId.contains('-mul')), isFalse);
      expect(african.any((m) => m.modelId.contains('-alv')), isFalse);
    });

    test('fetchAllAvailableModels includes private HF Fula and Xenova', () async {
      final service = TranslationModelService();
      final models = await service.fetchAllAvailableModels();
      expect(models.length, greaterThan(10));
      expect(
        models.any((m) => m.modelId == 'flutter-painter/french-fula'),
        isTrue,
      );
      expect(models.any((m) => m.modelId.startsWith('Xenova/')), isTrue);
      expect(models.any((m) => m.modelId == 'malinali-app/opus-mt-en-ha'), isTrue);
      expect(models.any((m) => m.modelId == 'assets/fr-pul'), isFalse);
    });

    test('preference JSON round-trips non-custom boot model fields', () {
      final boot = TranslationModelService.defaultBootModel;
      final restored = TranslationModel.fromPreferenceJson(boot.toPreferenceJson());
      expect(restored, isNotNull);
      expect(restored!.modelId, boot.modelId);
      expect(restored.isCustom, isFalse);
      expect(restored.isAsset, isFalse);
      expect(restored.requiresAuth, isFalse);
      expect(
        restored.sourceLang.localeIntl.locale.languageCode,
        'fr',
      );
      expect(
        restored.targetLang.localeIntl.locale.languageCode,
        'en',
      );
    });

    test('preference JSON round-trips private Fula model', () {
      final fula = TranslationModelService.privateModels.first;
      final restored = TranslationModel.fromPreferenceJson(fula.toPreferenceJson());
      expect(restored, isNotNull);
      expect(restored!.modelId, fula.modelId);
      expect(restored.requiresAuth, isTrue);
      expect(restored.isCustom, isFalse);
      expect(restored.downloadSizeHint, fula.downloadSizeHint);
    });
  });
}
