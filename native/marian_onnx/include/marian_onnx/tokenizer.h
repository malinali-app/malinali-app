#pragma once

#include "marian_onnx/types.h"

#include <string>
#include <vector>

namespace marian_onnx {

class SentencePiecePair {
 public:
  SentencePiecePair() = default;
  ~SentencePiecePair();

  SentencePiecePair(const SentencePiecePair&) = delete;
  SentencePiecePair& operator=(const SentencePiecePair&) = delete;

  SentencePiecePair(SentencePiecePair&& other) noexcept;
  SentencePiecePair& operator=(SentencePiecePair&& other) noexcept;

  /// Load source.spm + target.spm from [model_dir].
  static SentencePiecePair load(const std::string& model_dir);

  std::vector<int32_t> encode(const std::string& text) const;
  std::string decode(const std::vector<int32_t>& ids) const;

 private:
  void* enc_ = nullptr;
  void* dec_ = nullptr;
};

SpecialTokens load_special_tokens(const std::string& model_dir);

}  // namespace marian_onnx
