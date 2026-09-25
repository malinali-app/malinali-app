import 'package:flutter_test/flutter_test.dart';
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

    test('fetchAllAvailableModels fetches online models from Xenova and HF', () async {
      final service = TranslationModelService();
      final models = await service.fetchAllAvailableModels();
      // Must contain private models (fr-pul) and online Xenova models
      expect(models.length, greaterThan(10));
      expect(models.any((m) => m.modelId == 'assets/fr-pul'), isTrue);
      expect(models.any((m) => m.modelId.startsWith('Xenova/')), isTrue);
    });
  });
}
