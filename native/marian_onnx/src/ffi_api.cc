#include "marian_onnx/ffi_api.h"

#include "marian_onnx/decode.h"
#include "marian_onnx/ort_session.h"
#include "marian_onnx/tokenizer.h"

#include <cstdlib>
#include <cstring>
#include <exception>
#include <memory>
#include <string>
#include <vector>

namespace {

thread_local std::string g_last_error;

void set_error(const std::string& msg) { g_last_error = msg; }

struct Translator {
  std::unique_ptr<marian_onnx::Seq2SeqSession> session;
  marian_onnx::SentencePiecePair tokenizer;
  marian_onnx::SpecialTokens special;
};

char* dup_string(const std::string& s) {
  char* out = static_cast<char*>(std::malloc(s.size() + 1));
  if (out == nullptr) return nullptr;
  std::memcpy(out, s.data(), s.size());
  out[s.size()] = '\0';
  return out;
}

}  // namespace

extern "C" {

MARIAN_ONNX_API void* marian_onnx_load(const char* model_dir) {
  try {
    g_last_error.clear();
    if (model_dir == nullptr || model_dir[0] == '\0') {
      set_error("model_dir is empty");
      return nullptr;
    }
    auto t = std::make_unique<Translator>();
    t->session = marian_onnx::load_ort_session(model_dir);
    t->tokenizer = marian_onnx::SentencePiecePair::load(model_dir);
    t->special = marian_onnx::load_special_tokens(model_dir);
    return t.release();
  } catch (const std::exception& e) {
    set_error(e.what());
    return nullptr;
  } catch (...) {
    set_error("unknown error in marian_onnx_load");
    return nullptr;
  }
}

MARIAN_ONNX_API char* marian_onnx_translate(void* handle,
                                            const char* text,
                                            int32_t num_beams,
                                            int32_t max_new_tokens,
                                            double length_penalty,
                                            int32_t no_repeat_ngram_size) {
  try {
    g_last_error.clear();
    if (handle == nullptr) {
      set_error("null handle");
      return nullptr;
    }
    if (text == nullptr) text = "";
    std::string input(text);
    // Trim
    while (!input.empty() &&
           (input.front() == ' ' || input.front() == '\t' ||
            input.front() == '\n' || input.front() == '\r')) {
      input.erase(input.begin());
    }
    while (!input.empty() &&
           (input.back() == ' ' || input.back() == '\t' ||
            input.back() == '\n' || input.back() == '\r')) {
      input.pop_back();
    }
    if (input.empty()) {
      return dup_string("");
    }

    auto* t = static_cast<Translator*>(handle);
    auto ids = t->tokenizer.encode(input);
    ids.push_back(t->special.eos_token_id);

    marian_onnx::TranslationConfig cfg;
    cfg.num_beams = num_beams;
    cfg.max_new_tokens = max_new_tokens;
    cfg.length_penalty = length_penalty;
    cfg.no_repeat_ngram_size = no_repeat_ngram_size;

    auto generated =
        marian_onnx::generate(*t->session, ids, t->special, cfg);

    std::vector<int32_t> decode_ids;
    decode_ids.reserve(generated.size());
    for (int32_t id : generated) {
      if (id == t->special.decoder_start_token_id) continue;
      if (id == t->special.eos_token_id ||
          id == t->special.forced_eos_token_id) {
        break;
      }
      decode_ids.push_back(id);
    }

    return dup_string(t->tokenizer.decode(decode_ids));
  } catch (const std::exception& e) {
    set_error(e.what());
    return nullptr;
  } catch (...) {
    set_error("unknown error in marian_onnx_translate");
    return nullptr;
  }
}

MARIAN_ONNX_API void marian_onnx_string_free(char* s) {
  std::free(s);
}

MARIAN_ONNX_API void marian_onnx_free(void* handle) {
  delete static_cast<Translator*>(handle);
}

MARIAN_ONNX_API const char* marian_onnx_last_error(void) {
  return g_last_error.c_str();
}

}  // extern "C"
