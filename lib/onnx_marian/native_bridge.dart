import 'translation_config.dart';

/// Native FFI surface for Marian ONNX. Tests inject a fake implementation.
abstract class MarianOnnxNativeBridge {
  /// Load model folder; returns an opaque handle (pointer-sized int).
  int load(String modelDir);

  /// One-shot translate: entire autoregressive loop runs in native code.
  String translate(int handle, String text, OnnxTranslationConfig config);

  void free(int handle);
}
