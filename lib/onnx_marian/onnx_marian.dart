/// Isolated ONNX Marian translator (native KV-cache decode).
///
/// Windows boot uses this via TextTranslator; other platforms keep Candle.
library;

export 'ffi_bridge.dart';
export 'marian_onnx.dart';
export 'model_dir.dart';
export 'native_bridge.dart';
export 'translation_config.dart';
