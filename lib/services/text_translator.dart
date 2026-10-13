import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:malinali/onnx_marian/onnx_marian.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:marian_flutter/marian_flutter.dart';

/// Decode knobs shared by Candle and ONNX Marian.
class DecodeConfig {
  const DecodeConfig({
    this.numBeams = 2,
    this.maxNewTokens = 24,
    this.lengthPenalty = 1.2,
    this.noRepeatNgramSize = 3,
  });

  final int numBeams;
  final int maxNewTokens;
  final double lengthPenalty;
  final int noRepeatNgramSize;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DecodeConfig &&
          numBeams == other.numBeams &&
          maxNewTokens == other.maxNewTokens &&
          lengthPenalty == other.lengthPenalty &&
          noRepeatNgramSize == other.noRepeatNgramSize;

  @override
  int get hashCode =>
      Object.hash(numBeams, maxNewTokens, lengthPenalty, noRepeatNgramSize);
}

/// Interactive on-device defaults (beams=2 / 24 new tokens).
const DecodeConfig kStreetDecodeConfig = DecodeConfig();

/// Voice-mode decode: greedy decoding (numBeams=1) for 2x faster hops and
/// zero beam-fork KV cloning on spoken utterances.
const DecodeConfig kVoiceDecodeConfig = DecodeConfig(
  numBeams: 1,
  maxNewTokens: 64,
  lengthPenalty: 1.0,
  noRepeatNgramSize: 3,
);

/// Document-mode decode: longer outputs than street chat bubbles.
const DecodeConfig kDocumentTranslationConfig = DecodeConfig(
  numBeams: 2,
  maxNewTokens: 128,
  lengthPenalty: 1.2,
  noRepeatNgramSize: 3,
);

/// App-facing translator. Candle or ONNX; tests inject fakes.
abstract class TextTranslator {
  Future<String> translate(
    String text, {
    DecodeConfig config = kStreetDecodeConfig,
  });

  void dispose();
}

/// Candle / `marian_flutter` backend (written translation only).
class CandleTextTranslator implements TextTranslator {
  CandleTextTranslator(this._inner);

  final MarianService _inner;
  static bool _rustReady = false;

  /// Lazy `initRust` — voice launch does not load Candle.
  static Future<void> ensureRust() async {
    if (_rustReady) return;
    await MarianService.initRust();
    _rustReady = true;
  }

  @override
  Future<String> translate(
    String text, {
    DecodeConfig config = kStreetDecodeConfig,
  }) {
    return _inner.translate(
      text,
      config: TranslationConfig(
        numBeams: config.numBeams,
        maxNewTokens: config.maxNewTokens,
        lengthPenalty: config.lengthPenalty,
        noRepeatNgramSize: config.noRepeatNgramSize,
      ),
    );
  }

  @override
  void dispose() {}
}

/// Native ONNX backend (`libmarian_onnx.so` on Android, DLL on Windows).
///
/// When loaded without a custom [bridge], both `marian_onnx_load` and
/// `marian_onnx_translate` execute inside `Isolate.run` so the main UI
/// isolate never blocks during ONNX session creation or beam search.
class OnnxTextTranslator implements TextTranslator {
  OnnxTextTranslator(this._inner)
      : _handle = null,
        _libraryPath = null;

  OnnxTextTranslator._isolate(int handle, String libraryPath)
      : _inner = null,
        _handle = handle,
        _libraryPath = libraryPath;

  final MarianOnnx? _inner;
  final int? _handle;
  final String? _libraryPath;
  bool _disposed = false;

  factory OnnxTextTranslator.load(
    String directory, {
    MarianOnnxNativeBridge? bridge,
  }) {
    return OnnxTextTranslator(
      MarianOnnx.load(
        directory,
        bridge: bridge ?? MarianOnnxFfiBridge.openDefault(),
      ),
    );
  }

  /// Asynchronously load the ONNX session on a background isolate when using
  /// the default FFI bridge, keeping the UI isolate responsive.
  static Future<OnnxTextTranslator> loadAsync(
    String directory, {
    MarianOnnxNativeBridge? bridge,
  }) async {
    if (bridge != null) {
      return OnnxTextTranslator.load(directory, bridge: bridge);
    }
    assertMarianOnnxModelDir(directory);
    final libPath = MarianOnnxFfiBridge.resolveDllPath();
    if (libPath == null) {
      throw StateError(
        'marian_onnx native library not found (Windows DLL or Android .so)',
      );
    }
    final handle = await Isolate.run(
      () => MarianOnnxFfiBridge.open(libPath).load(directory),
    );
    return OnnxTextTranslator._isolate(handle, libPath);
  }

  @override
  Future<String> translate(
    String text, {
    DecodeConfig config = kStreetDecodeConfig,
  }) async {
    if (_disposed) {
      throw StateError('MarianOnnx already freed');
    }
    final onnxConfig = OnnxTranslationConfig(
      numBeams: config.numBeams,
      maxNewTokens: config.maxNewTokens,
      lengthPenalty: config.lengthPenalty,
      noRepeatNgramSize: config.noRepeatNgramSize,
    );
    final inner = _inner;
    if (inner != null) {
      return inner.translate(text, config: onnxConfig);
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final handle = _handle!;
    final libPath = _libraryPath!;
    return Isolate.run(
      () => MarianOnnxFfiBridge.open(libPath).translate(
        handle,
        trimmed,
        onnxConfig,
      ),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final inner = _inner;
    if (inner != null) {
      inner.free();
      return;
    }
    final handle = _handle;
    final libPath = _libraryPath;
    if (handle != null && libPath != null) {
      MarianOnnxFfiBridge.open(libPath).free(handle);
    }
  }
}

/// Loads Candle or ONNX from a model id + on-disk folder.
class TextTranslatorLoader {
  static Future<TextTranslator> load({
    required TranslationModel model,
    String? directory,
    MarianOnnxNativeBridge? onnxBridge,
  }) async {
    if (model.isAsset) {
      await CandleTextTranslator.ensureRust();
      return CandleTextTranslator(
        await MarianService.loadFromAssets(assetFolder: model.modelId),
      );
    }
    if (directory == null || directory.isEmpty) {
      throw ArgumentError('directory required for non-asset models');
    }
    if (model.isOnnx) {
      if (!Platform.isAndroid && !Platform.isWindows) {
        throw UnsupportedError(
          'ONNX Marian is Android/Windows in this slice',
        );
      }
      return OnnxTextTranslator.loadAsync(directory, bridge: onnxBridge);
    }
    await CandleTextTranslator.ensureRust();
    return CandleTextTranslator(
      await MarianService.loadFromDirectory(directory),
    );
  }

  static Future<TextTranslator> downloadAndLoad({
    required TranslationModel model,
    required TranslationModelService modelService,
    MarianOnnxNativeBridge? onnxBridge,
  }) async {
    if (model.isAsset) {
      return load(model: model, onnxBridge: onnxBridge);
    }
    final dir = await modelService.downloadModel(model);
    return load(
      model: model,
      directory: dir.path,
      onnxBridge: onnxBridge,
    );
  }
}
