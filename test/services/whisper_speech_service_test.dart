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

  test('downloadSpecialist writes onnx files under whisper_onnx', () async {
    final dio = Dio();
    dio.httpClientAdapter = _FakeAdapter(List<int>.filled(32, 7));
    final service = WhisperSpeechService(dio: dio);
    final pack = whisperSpecialistById('yoruba-small')!;

    expect(await service.isSpecialistDownloaded(pack), isFalse);
    final dir = await service.downloadSpecialist(pack);
    expect(Directory(dir).existsSync(), isTrue);
    expect(File(p.join(dir, 'encoder.int8.onnx')).existsSync(), isTrue);
    expect(File(p.join(dir, 'decoder.int8.onnx')).existsSync(), isTrue);
    expect(File(p.join(dir, 'tokens.txt')).existsSync(), isTrue);
    expect(p.basename(dir), 'yoruba-small');
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
