import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/marian_runtime.dart';
import 'package:malinali/services/translation_model_service.dart';

import 'translate_page_test.mocks.dart';

void main() {
  tearDown(() {
    MarianRuntime.instance.clear();
  });

  test('MarianRuntime attach / clear tracks process-lifetime session', () {
    final runtime = MarianRuntime.instance;
    expect(runtime.isReady, isFalse);

    final marian = MockMarianService();
    final model = TranslationModelService.defaultBootModel;
    runtime.attach(marian, model);

    expect(runtime.isReady, isTrue);
    expect(runtime.marian, same(marian));
    expect(runtime.model?.modelId, model.modelId);

    runtime.clear();
    expect(runtime.isReady, isFalse);
    expect(runtime.marian, isNull);
    expect(runtime.model, isNull);
  });
}
