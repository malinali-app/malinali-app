#pragma once

#include "marian_onnx/types.h"

#include <functional>
#include <stdexcept>
#include <utility>

namespace marian_onnx {

struct FakePast final : PastKeyValues {
  explicit FakePast(int length) : length_(length) {}
  int past_length() const override { return length_; }
  std::unique_ptr<PastKeyValues> clone() const override {
    return std::make_unique<FakePast>(length_);
  }
  int length_;
};

struct FakeEncoder final : EncoderStates {
  explicit FakeEncoder(std::vector<int32_t> ids) : input_ids(std::move(ids)) {}
  std::vector<int32_t> input_ids;
};

/// Scripted session for unit tests: records every call and returns fixed logits.
class FakeSession final : public Seq2SeqSession {
 public:
  using LogitFn = std::function<Logits(int step, int32_t token_id, int past_len)>;

  FakeSession(int vocab, LogitFn fn) : vocab_(vocab), logit_fn_(std::move(fn)) {}

  int vocab_size() const override { return vocab_; }

  int encode_calls = 0;
  std::vector<int> decode_input_lengths;
  std::vector<int> past_lengths_seen;
  std::vector<int32_t> tokens_seen;
  std::vector<int> start_positions;

  std::unique_ptr<EncoderStates> encode(
      const std::vector<int32_t>& input_ids) override {
    ++encode_calls;
    return std::make_unique<FakeEncoder>(input_ids);
  }

  std::pair<Logits, std::unique_ptr<PastKeyValues>> decode_step(
      int32_t token_id,
      const EncoderStates& /*encoder*/,
      PastKeyValues* past,
      int start_pos) override {
    const int past_len = past == nullptr ? 0 : past->past_length();
    decode_input_lengths.push_back(1);
    past_lengths_seen.push_back(past_len);
    tokens_seen.push_back(token_id);
    start_positions.push_back(start_pos);

    const int step = static_cast<int>(tokens_seen.size()) - 1;
    Logits logits = logit_fn_(step, token_id, past_len);
    if (static_cast<int>(logits.size()) != vocab_) {
      throw std::runtime_error("fake logits size mismatch");
    }
    // Present length = past + 1 (one new position).
    return {std::move(logits), std::make_unique<FakePast>(past_len + 1)};
  }

 private:
  int vocab_;
  LogitFn logit_fn_;
};

}  // namespace marian_onnx
