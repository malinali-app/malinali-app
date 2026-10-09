import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:malinali/services/tts_service.dart';
import 'package:languages_dart/languages_dart.dart';

class MockFlutterTts extends Mock implements FlutterTts {
  @override
  Future<dynamic> setVolume(double? volume) => super.noSuchMethod(
        Invocation.method(#setVolume, [volume]),
        returnValue: Future.value(1),
      );
  @override
  Future<dynamic> setSpeechRate(double? rate) => super.noSuchMethod(
        Invocation.method(#setSpeechRate, [rate]),
        returnValue: Future.value(1),
      );
  @override
  Future<dynamic> setPitch(double? pitch) => super.noSuchMethod(
        Invocation.method(#setPitch, [pitch]),
        returnValue: Future.value(1),
      );
  @override
  Future<dynamic> isLanguageAvailable(String? lang) => super.noSuchMethod(
        Invocation.method(#isLanguageAvailable, [lang]),
        returnValue: Future.value(true),
      );
  @override
  Future<dynamic> setLanguage(String? lang) => super.noSuchMethod(
        Invocation.method(#setLanguage, [lang]),
        returnValue: Future.value(1),
      );
  @override
  Future<dynamic> speak(String? text, {bool focus = false}) => super.noSuchMethod(
        Invocation.method(#speak, [text]),
        returnValue: Future.value(1),
      );
  @override
  Future<dynamic> stop() => super.noSuchMethod(
        Invocation.method(#stop, []),
        returnValue: Future.value(1),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  test('Empty text should not trigger speak', () async {
    final service = TtsService();
    final result = await service.speak('', Languages.french);
    expect(result, isFalse);
  });
}
