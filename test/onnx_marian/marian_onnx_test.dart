import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/onnx_marian/ffi_bridge.dart';
import 'package:malinali/onnx_marian/marian_onnx.dart';
import 'package:malinali/onnx_marian/model_dir.dart';
import 'package:malinali/onnx_marian/native_bridge.dart';
import 'package:malinali/onnx_marian/translation_config.dart';
import 'package:malinali/services/text_translator.dart';
import 'package:path/path.dart' as p;

class _FakeBridge implements MarianOnnxNativeBridge {
  int loadCalls = 0;
  int translateCalls = 0;
  int freeCalls = 0;
  String? lastText;
  OnnxTranslationConfig? lastConfig;

  @override
  int load(String modelDir) {
    loadCalls++;
    return 42;
  }

  @override
  String translate(int handle, String text, OnnxTranslationConfig config) {
    translateCalls++;
    lastText = text;
    lastConfig = config;
    expect(handle, 42);
    return 'translated:$text';
  }

  @override
  void free(int handle) {
    freeCalls++;
    expect(handle, 42);
  }
}

Directory _tempModelDir({bool withPast = true}) {
  final dir = Directory.systemTemp.createTempSync('marian_onnx_');
  for (final name in kMarianOnnxRequiredFiles) {
    if (!withPast && name == 'decoder_with_past_model.onnx') continue;
    File(p.join(dir.path, name)).writeAsStringSync('stub');
  }
  return dir;
}

void main() {
  test('load throws when decoder_with_past_model.onnx is missing', () {
    final dir = _tempModelDir(withPast: false);
    addTearDown(() => dir.deleteSync(recursive: true));
    final bridge = _FakeBridge();

    expect(
      () => MarianOnnx.load(dir.path, bridge: bridge),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('decoder_with_past_model.onnx'),
        ),
      ),
    );
    expect(bridge.loadCalls, 0);
  });

  test('empty text does not call native translate', () {
    final dir = _tempModelDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final bridge = _FakeBridge();
    final marian = MarianOnnx.load(dir.path, bridge: bridge);

    expect(marian.translate(''), '');
    expect(marian.translate('   '), '');
    expect(bridge.translateCalls, 0);
    expect(bridge.loadCalls, 1);

    marian.free();
    expect(bridge.freeCalls, 1);
  });

  test('non-empty text calls native translate exactly once', () {
    final dir = _tempModelDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final bridge = _FakeBridge();
    final marian = MarianOnnx.load(dir.path, bridge: bridge);

    final out = marian.translate('Hello world');
    expect(out, 'translated:Hello world');
    expect(bridge.translateCalls, 1);
    expect(bridge.lastText, 'Hello world');
    expect(bridge.lastConfig, kOnnxStreetTranslationConfig);
  });

  test('OnnxTextTranslator.loadAsync and translate run on background isolate with real DLL', () async {
    final dllPath = MarianOnnxFfiBridge.resolveDllPath();
    if (dllPath == null) return;
    final home = Platform.environment['USERPROFILE'];
    if (home == null) return;
    final frEnDir = p.join(
      home,
      'Documents',
      'Malinali_do_not_delete',
      'marian_models',
      'malinali-app_opus-mt_tiny_fra-eng-onnx',
    );
    if (!Directory(frEnDir).existsSync()) return;

    final translator = await OnnxTextTranslator.loadAsync(frEnDir);
    try {
      expect(await translator.translate('   '), '');
      final out = await translator.translate("Je m'appelle Pierre.");
      expect(out.toLowerCase(), contains('peter'));
    } finally {
      translator.dispose();
    }
  });

  test('real native DLL translates FR→EN and EN→WO when models are present', () {
    final dllPath = MarianOnnxFfiBridge.resolveDllPath();
    if (dllPath == null) return;
    final home = Platform.environment['USERPROFILE'];
    if (home == null) return;
    final frEnDir = p.join(
      home,
      'Documents',
      'Malinali_do_not_delete',
      'marian_models',
      'malinali-app_opus-mt_tiny_fra-eng-onnx',
    );
    final enWoDir = p.join(
      home,
      'Documents',
      'Malinali_do_not_delete',
      'marian_models',
      'malinali-app_traduction-en-wolof-onnx',
    );
    if (!Directory(frEnDir).existsSync() || !Directory(enWoDir).existsSync()) {
      return;
    }

    final bridge = MarianOnnxFfiBridge.open(dllPath);
    final frEn = MarianOnnx.load(frEnDir, bridge: bridge);
    final en = frEn.translate(
      "Je m'appelle Pierre.",
      config: const OnnxTranslationConfig(
        numBeams: 2,
        maxNewTokens: 128,
        lengthPenalty: 1.2,
        noRepeatNgramSize: 3,
      ),
    );
    frEn.free();
    expect(en.toLowerCase(), contains('peter'));

    final enWo = MarianOnnx.load(enWoDir, bridge: bridge);
    final wo = enWo.translate(
      '>>wol<< $en',
      config: const OnnxTranslationConfig(
        numBeams: 2,
        maxNewTokens: 128,
        lengthPenalty: 1.2,
        noRepeatNgramSize: 3,
      ),
    );
    enWo.free();
    expect(wo.trim(), isNotEmpty);
  });

  test('merged decoder (decoder_model_merged.onnx) matches split decoder output', () {
    final dllPath = MarianOnnxFfiBridge.resolveDllPath();
    if (dllPath == null) return;
    final mergedSource = Directory('tools/export_marian_onnx/out/fr-en-tiny');
    if (!mergedSource.existsSync()) return;
    final mergedFile = File(p.join(mergedSource.path, 'decoder_model_merged.onnx'));
    if (!mergedFile.existsSync()) return;

    // Create a temp model dir with ONLY encoder_model.onnx + decoder_model_merged.onnx
    // (no decoder_model.onnx or decoder_with_past_model.onnx) to verify Plan 2.
    final tempMergedDir = Directory.systemTemp.createTempSync('marian_merged_');
    addTearDown(() => tempMergedDir.deleteSync(recursive: true));
    for (final name in [
      'encoder_model.onnx',
      'decoder_model_merged.onnx',
      'source.spm',
      'target.spm',
      'tokenizer_config.json',
      'generation_config.json',
      'config.json',
    ]) {
      File(p.join(mergedSource.path, name))
          .copySync(p.join(tempMergedDir.path, name));
    }

    final bridge = MarianOnnxFfiBridge.open(dllPath);
    final merged = MarianOnnx.load(tempMergedDir.path, bridge: bridge);
    try {
      final greedyOut = merged.translate(
        "Je m'appelle Pierre.",
        config: const OnnxTranslationConfig(
          numBeams: 1,
          maxNewTokens: 32,
          lengthPenalty: 1.0,
          noRepeatNgramSize: 3,
        ),
      );
      expect(greedyOut.toLowerCase(), contains('peter'));

      final beamOut = merged.translate(
        "Je m'appelle Pierre.",
        config: const OnnxTranslationConfig(
          numBeams: 2,
          maxNewTokens: 32,
          lengthPenalty: 1.2,
          noRepeatNgramSize: 3,
        ),
      );
      expect(beamOut.toLowerCase(), contains('peter'));
    } finally {
      merged.free();
    }
  });
}
