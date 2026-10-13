#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace marian_onnx {

/// Decode hyperparameters matching Malinali street-mode / HuggingFace Marian.
struct TranslationConfig {
  int num_beams = 2;
  int max_new_tokens = 24;
  double length_penalty = 1.2;
  int no_repeat_ngram_size = 3;
};

/// Special token ids from generation_config / config.json.
struct SpecialTokens {
  int32_t pad_token_id = 0;
  int32_t eos_token_id = 0;
  int32_t decoder_start_token_id = 0;
  int32_t forced_eos_token_id = 0;
  int32_t unk_token_id = 1;
};

/// Opaque past key/value state owned by a Seq2SeqSession implementation.
struct PastKeyValues {
  virtual ~PastKeyValues() = default;
  /// Sequence length already covered by this cache (0 before any decode step).
  virtual int past_length() const = 0;
  virtual std::unique_ptr<PastKeyValues> clone() const = 0;
};

/// Encoder output reused for every decoder step of one utterance.
struct EncoderStates {
  virtual ~EncoderStates() = default;
};

/// Softmax-space logits for the next token (vocab size).
using Logits = std::vector<float>;

/// Abstract encoder / decoder used by the native generation loop.
///
/// Implementations must:
/// - run encode once per utterance
/// - accept a single new token id per decode step
/// - keep present KV in native memory (never expose tensors to Dart)
class Seq2SeqSession {
 public:
  virtual ~Seq2SeqSession() = default;

  virtual int vocab_size() const = 0;

  virtual std::unique_ptr<EncoderStates> encode(
      const std::vector<int32_t>& input_ids) = 0;

  /// Step 0: decoder_model with length-1 input (decoder_start).
  /// Later steps: decoder_with_past with length-1 input and [past].
  /// Returns logits for the new position and updated present KV.
  virtual std::pair<Logits, std::unique_ptr<PastKeyValues>> decode_step(
      int32_t token_id,
      const EncoderStates& encoder,
      PastKeyValues* past,  // nullptr on step 0
      int start_pos) = 0;
};

}  // namespace marian_onnx
