#pragma once

#include "marian_onnx/types.h"

#include <memory>
#include <string>

namespace marian_onnx {

/// ONNX Runtime encoder + decoder + decoder_with_past.
///
/// Requires decoder_model to emit present KV tensors. Load fails otherwise.
std::unique_ptr<Seq2SeqSession> load_ort_session(const std::string& model_dir);

}  // namespace marian_onnx
