#pragma once

#include "marian_onnx/types.h"

#include <vector>

namespace marian_onnx {

/// Run encoder once, then greedy or incremental beam decode with KV cache.
///
/// Every decoder step feeds exactly one new token id. Past tensors stay inside
/// [session]; they are never copied to the caller.
std::vector<int32_t> generate(
    Seq2SeqSession& session,
    const std::vector<int32_t>& encoder_input_ids,
    const SpecialTokens& special,
    const TranslationConfig& config);

float normalized_score(float score, int len, double length_penalty);

void apply_no_repeat_ngram(const std::vector<int32_t>& tokens,
                           std::vector<float>& scores,
                           int ngram_size);

void log_softmax_inplace(std::vector<float>& scores);

int argmax(const std::vector<float>& scores);

std::vector<int> top_k_indices(const std::vector<float>& scores, int k);

}  // namespace marian_onnx
