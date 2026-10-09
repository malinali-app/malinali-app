import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/whisper_speech_service.dart';
import 'package:malinali/services/whisper_specialist_models.dart';
import 'package:path/path.dart' as p;

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.bytes);

  final List<int> bytes;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/octet-stream'],
        Headers.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocs;

  setUp(() async {
    tempDocs = await Directory.systemTemp.createTemp('whisper_svc_');
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory' ||
          methodCall.method == 'getApplicationSupportDirectory') {
        return tempDocs.path;
      }
      return null;
    });
  });

  tearDown(() async {
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler(null);
    if (tempDocs.existsSync()) {
      tempDocs.deleteSync(recursive: true);
    }
  });

  test('downloadSpecialist writes ggml file under whisper_specialists', () async {
    final dio = Dio();
    dio.httpClientAdapter = _FakeAdapter(List<int>.filled(32, 7));
    final service = WhisperSpeechService(dio: dio);
    final pack = whisperSpecialistById('yoruba-small')!;

    expect(await service.isSpecialistDownloaded(pack), isFalse);
    final path = await service.downloadSpecialist(pack);
    expect(File(path).existsSync(), isTrue);
    expect(await File(path).length(), 32);
    expect(p.basename(path), 'yoruba-small.bin');
    expect(await service.isSpecialistDownloaded(pack), isTrue);
  });

  test('setActivePack rejects unavailable packs', () async {
    final service = WhisperSpeechService();
    final blocked = whisperSpecialistById('dioula-tiny')!;
    expect(
      () => service.setActivePack(blocked),
      throwsA(isA<StateError>()),
    );
    expect(service.isDefaultTranslatePack, isTrue);
  });

  test('setActivePack switches specialist and engineId', () async {
    final dio = Dio();
    dio.httpClientAdapter = _FakeAdapter([1, 2, 3, 4]);
    final service = WhisperSpeechService(dio: dio);
    final pack = whisperSpecialistById('swahili-small')!;
    await service.downloadSpecialist(pack);
    await service.setActivePack(pack);
    expect(service.activeSpecialist?.id, 'swahili-small');
    expect(service.isDefaultTranslatePack, isFalse);
    expect(service.engineId, 'whisper-swahili-small');
    expect(await service.isModelPresent(), isTrue);

    await service.setActivePack(null);
    expect(service.isDefaultTranslatePack, isTrue);
    expect(service.engineId, 'whisper-tiny');
  });
}
