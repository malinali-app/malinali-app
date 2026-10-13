import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/marian_runtime.dart';
import 'package:malinali/services/text_translator.dart';
import 'package:malinali/services/translation_model_service.dart';

import 'translate_page_test.mocks.dart';

void main() {
  tearDown(() {
    MarianRuntime.instance.clear();
  });

  test('MarianRuntime attach / clear tracks process-lifetime session', () {
    final runtime = MarianRuntime.instance;
    expect(runtime.isReady, isFalse);

    final translator = CandleTextTranslator(MockMarianService());
    final model = TranslationModelService.defaultBootModel;
    runtime.attach(translator, model);

    expect(runtime.isReady, isTrue);
    expect(runtime.translator, same(translator));
    expect(runtime.model?.modelId, model.modelId);

    runtime.clear();
    expect(runtime.isReady, isFalse);
    expect(runtime.translator, isNull);
    expect(runtime.model, isNull);
  });
}
