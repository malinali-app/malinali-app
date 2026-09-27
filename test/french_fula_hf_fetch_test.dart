import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/generated/hf_token.g.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:path/path.dart' as p;

/// Avoid recursion: [HttpClient] factory always calls [HttpOverrides.createHttpClient].
class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    try {
      return HttpClient(context: context);
    } finally {
      HttpOverrides.global = previous is HttpOverrides ? previous : this;
    }
  }
}

/// Live HF checks for the private Candle pack (needs network + embedded read token).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  late Directory tempDocs;

  setUp(() async {
    HttpOverrides.global = _RealHttpOverrides();
    tempDocs = await Directory.systemTemp.createTemp('malinali_hf_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tempDocs.path;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tempDocs.exists()) {
      await tempDocs.delete(recursive: true);
    }
  });

  test('embedded HF read token is present and looks valid', () {
    final token = hfReadToken();
    expect(token.startsWith('hf_'), isTrue);
    expect(token.length, greaterThan(20));
  });

  test('authenticated GET reaches french-fula Candle metadata files', () async {
    final dio = Dio(
      BaseOptions(
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    final headers = {'Authorization': 'Bearer ${hfReadToken()}'};
    const repo = 'flutter-painter/french-fula';

    for (final name in ['config.json', 'tokenizer-enc.json', 'tokenizer-dec.json']) {
      final url = 'https://huggingface.co/$repo/resolve/main/$name';
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
        ),
      );
      expect(response.statusCode, 200, reason: '$name status');
      expect(response.data, isNotNull);
      expect(response.data!.length, greaterThan(500), reason: '$name body');
    }

    final weightsUrl =
        'https://huggingface.co/$repo/resolve/main/model.safetensors';
    final partial = await dio.get<List<int>>(
      weightsUrl,
      options: Options(
        headers: {
          ...headers,
          'Range': 'bytes=0-1023',
        },
        responseType: ResponseType.bytes,
        validateStatus: (s) => s == 200 || s == 206,
      ),
    );
    expect(partial.statusCode, anyOf(200, 206));
    expect(partial.data!.length, greaterThan(0));
    final total = partial.headers.value('content-range');
    if (total != null) {
      final size = int.tryParse(total.split('/').last);
      expect(size, greaterThan(200000000), reason: 'content-range $total');
    }
  });

  test(
    'downloadModel caches french-fula config + dual tokenizers + weights',
    () async {
      final service = TranslationModelService();
      final model = TranslationModelService.privateModels.first;
      expect(model.modelId, 'flutter-painter/french-fula');
      expect(model.requiresAuth, isTrue);

      final dir = await service.downloadModel(model);

      Future<int> sizeOf(String name) async {
        final file = File(p.join(dir.path, name));
        expect(await file.exists(), isTrue, reason: 'missing $name');
        return file.length();
      }

      expect(await sizeOf('config.json'), greaterThan(500));
      expect(await sizeOf('tokenizer-enc.json'), greaterThan(100000));
      expect(await sizeOf('tokenizer-dec.json'), greaterThan(100000));
      expect(await sizeOf('model.safetensors'), greaterThan(200000000));

      final again = await service.downloadModel(model);
      expect(again.path, dir.path);
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
