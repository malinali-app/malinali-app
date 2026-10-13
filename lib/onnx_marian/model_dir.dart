import 'dart:io';

import 'package:path/path.dart' as p;

/// Files required for Marian ONNX with incremental KV-cache decode.
const List<String> kMarianOnnxRequiredFiles = [
  'encoder_model.onnx',
  'decoder_model.onnx',
  'decoder_with_past_model.onnx',
  'source.spm',
  'target.spm',
  'tokenizer_config.json',
  'generation_config.json',
  'config.json',
];

const String kMarianOnnxMergedDecoderFile = 'decoder_model_merged.onnx';

/// Throws [StateError] listing every missing required file.
///
/// Accepts either `decoder_model_merged.onnx` OR the pair
/// (`decoder_model.onnx` + `decoder_with_past_model.onnx`).
void assertMarianOnnxModelDir(String modelDir) {
  final hasMerged =
      File(p.join(modelDir, kMarianOnnxMergedDecoderFile)).existsSync();
  final missing = <String>[];
  for (final name in kMarianOnnxRequiredFiles) {
    if (hasMerged &&
        (name == 'decoder_model.onnx' ||
            name == 'decoder_with_past_model.onnx')) {
      continue;
    }
    final file = File(p.join(modelDir, name));
    if (!file.existsSync()) {
      missing.add(name);
    }
  }
  if (missing.isEmpty) return;
  throw StateError(
    'Marian ONNX model dir incomplete ($modelDir). Missing: ${missing.join(', ')}',
  );
}
