import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/services/speech_recognition_service.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:record/record.dart';

class FakeAudioRecorder extends Fake implements AudioRecorder {
  bool _recording = false;
  bool stopCalled = false;
  bool cancelCalled = false;
  final StreamController<Uint8List> _streamController =
      StreamController<Uint8List>.broadcast();

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    _recording = true;
    stopCalled = false;
    return _streamController.stream;
  }

  @override
  Future<String?> stop() async {
    _recording = false;
    stopCalled = true;
    return null;
  }

  @override
  Future<void> cancel() async {
    _recording = false;
    cancelCalled = true;
  }

  @override
  Future<bool> isRecording() async => _recording;

  @override
  Future<void> dispose() async {
    await _streamController.close();
  }
}

void main() {
  group('SpeechRecognitionService Recording Lifecycle', () {
    test('startListening starts audio stream and stopListening stops recorder cleanly', () async {
      final fakeRecorder = FakeAudioRecorder();
      final service = SpeechRecognitionService(
        audioRecorder: fakeRecorder,
        modelService: VoskModelService(),
      );

      expect(service.isListening, isFalse);

      final stream = await fakeRecorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits),
      );
      expect(await fakeRecorder.isRecording(), isTrue);

      await service.stopListening();
      expect(service.isListening, isFalse);
      expect(fakeRecorder.stopCalled, isTrue);
      expect(await fakeRecorder.isRecording(), isFalse);
    });

    test('Calling stopListening is safe and sets isListening to false', () async {
      final fakeRecorder = FakeAudioRecorder();
      final service = SpeechRecognitionService(
        audioRecorder: fakeRecorder,
        modelService: VoskModelService(),
      );

      // Should not throw even when not started
      await service.stopListening();
      expect(service.isListening, isFalse);
    });
  });
}
