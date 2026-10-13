import 'model_dir.dart';
import 'native_bridge.dart';
import 'translation_config.dart';

/// Isolated ONNX Marian translator: one native call per [translate].
///
/// Does not import Flutter or `marian_flutter`. Generation (beam search + KV
/// cache) runs entirely inside the native library.
class MarianOnnx {
  MarianOnnx._(this._bridge, this._handle, this.modelDir);

  final MarianOnnxNativeBridge _bridge;
  final int _handle;
  final String modelDir;
  bool _freed = false;

  /// Validate [modelDir], then load via [bridge].
  static MarianOnnx load(
    String modelDir, {
    required MarianOnnxNativeBridge bridge,
  }) {
    assertMarianOnnxModelDir(modelDir);
    final handle = bridge.load(modelDir);
    return MarianOnnx._(bridge, handle, modelDir);
  }

  /// Empty [text] returns "" without calling native translate.
  String translate(
    String text, {
    OnnxTranslationConfig config = kOnnxStreetTranslationConfig,
  }) {
    if (_freed) {
      throw StateError('MarianOnnx already freed');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    return _bridge.translate(_handle, trimmed, config);
  }

  void free() {
    if (_freed) return;
    _freed = true;
    _bridge.free(_handle);
  }
}
