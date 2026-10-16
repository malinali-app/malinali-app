import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/wav_pcm_info.dart';
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
    expect(service.engineId, 'sherpa-swahili-small');
    expect(await service.isModelPresent(), isTrue);

    await service.setActivePack(null);
    expect(service.isDefaultTranslatePack, isTrue);
    expect(service.engineId, 'whisper-tiny');
  });

  test('openPlaceholderWav creates the file before any audio arrives', () async {
    final file = File(p.join(tempDocs.path, 'early.wav'));
    final sink = await openPlaceholderWav(file.path);
    expect(file.existsSync(), isTrue);
    expect(await file.length(), 44);
    await sink.close();
  });

  test('repairWavHeader patches the placeholder without growing the file', () async {
    final file = File(p.join(tempDocs.path, 'live.wav'));
    final header = ByteData(44);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }
    ascii(0, 'RIFF');
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 16000, Endian.little);
    header.setUint32(28, 32000, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    final pcm = Uint8List(320);
    for (var i = 0; i < pcm.length; i++) {
      pcm[i] = i % 255;
    }
    await file.writeAsBytes([...header.buffer.asUint8List(), ...pcm]);
    final before = await file.length();

    await repairWavHeader(file.path);

    final after = await file.readAsBytes();
    expect(after.length, before);
    final info = WavPcmInfo.parse(after);
    expect(info.dataByteCount, 320);
    expect(info.dataOffset, 44);
    expect(after.sublist(44), pcm);
  });
}
