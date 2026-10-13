#include "marian_onnx/tokenizer.h"

#include <fstream>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <utility>

#include <sentencepiece_processor.h>

namespace marian_onnx {
namespace {

std::string join_path(const std::string& dir, const std::string& name) {
  if (dir.empty()) return name;
  const char last = dir.back();
  if (last == '/' || last == '\\') return dir + name;
  return dir + "/" + name;
}

std::string read_file(const std::string& path) {
  std::ifstream in(path);
  if (!in) throw std::runtime_error("cannot open " + path);
  std::ostringstream ss;
  ss << in.rdbuf();
  return ss.str();
}

bool extract_int(const std::string& json, const std::string& key, int32_t& out) {
  // Matches "key": 123 or "key":123
  const std::regex re("\"" + key + "\"\\s*:\\s*(-?\\d+)");
  std::smatch m;
  if (!std::regex_search(json, m, re)) return false;
  out = static_cast<int32_t>(std::stol(m[1].str()));
  return true;
}

}  // namespace

SentencePiecePair::~SentencePiecePair() {
  delete static_cast<sentencepiece::SentencePieceProcessor*>(enc_);
  delete static_cast<sentencepiece::SentencePieceProcessor*>(dec_);
  enc_ = nullptr;
  dec_ = nullptr;
}

SentencePiecePair::SentencePiecePair(SentencePiecePair&& other) noexcept
    : enc_(other.enc_), dec_(other.dec_) {
  other.enc_ = nullptr;
  other.dec_ = nullptr;
}

SentencePiecePair& SentencePiecePair::operator=(
    SentencePiecePair&& other) noexcept {
  if (this != &other) {
    delete static_cast<sentencepiece::SentencePieceProcessor*>(enc_);
    delete static_cast<sentencepiece::SentencePieceProcessor*>(dec_);
    enc_ = other.enc_;
    dec_ = other.dec_;
    other.enc_ = nullptr;
    other.dec_ = nullptr;
  }
  return *this;
}

SentencePiecePair SentencePiecePair::load(const std::string& model_dir) {
  SentencePiecePair pair;
  auto* enc = new sentencepiece::SentencePieceProcessor();
  auto* dec = new sentencepiece::SentencePieceProcessor();
  const auto enc_path = join_path(model_dir, "source.spm");
  const auto dec_path = join_path(model_dir, "target.spm");
  const auto st1 = enc->Load(enc_path);
  if (!st1.ok()) {
    delete enc;
    delete dec;
    throw std::runtime_error("source.spm: " + st1.ToString());
  }
  const auto st2 = dec->Load(dec_path);
  if (!st2.ok()) {
    delete enc;
    delete dec;
    throw std::runtime_error("target.spm: " + st2.ToString());
  }
  pair.enc_ = enc;
  pair.dec_ = dec;
  return pair;
}

std::vector<int32_t> SentencePiecePair::encode(const std::string& text) const {
  auto* enc = static_cast<sentencepiece::SentencePieceProcessor*>(enc_);
  // MarianTokenizer lifts a leading >>xx<< code out of SentencePiece and
  // emits that vocab id first. Encoding the whole string would insert an
  // extra whitespace piece in front of the code.
  std::string body = text;
  std::vector<int32_t> prefix;
  if (body.size() >= 4 && body[0] == '>' && body[1] == '>') {
    const auto end = body.find("<<");
    if (end != std::string::npos && end <= 12) {
      const std::string code = body.substr(0, end + 2);
      const int id = enc->PieceToId(code);
      if (id >= 0 && enc->IdToPiece(id) == code) {
        prefix.push_back(static_cast<int32_t>(id));
        body = body.substr(end + 2);
      }
    }
  }
  std::vector<int> ids;
  const auto st = enc->Encode(body, &ids);
  if (!st.ok()) throw std::runtime_error("encode: " + st.ToString());
  prefix.insert(prefix.end(), ids.begin(), ids.end());
  return prefix;
}

std::string SentencePiecePair::decode(const std::vector<int32_t>& ids) const {
  auto* dec = static_cast<sentencepiece::SentencePieceProcessor*>(dec_);
  std::vector<int> raw(ids.begin(), ids.end());
  std::string out;
  const auto st = dec->Decode(raw, &out);
  if (!st.ok()) throw std::runtime_error("decode: " + st.ToString());
  return out;
}

SpecialTokens load_special_tokens(const std::string& model_dir) {
  SpecialTokens t;
  // Defaults match typical Helsinki Marian.
  t.pad_token_id = 65000;
  t.eos_token_id = 0;
  t.unk_token_id = 1;
  t.decoder_start_token_id = 65000;
  t.forced_eos_token_id = 0;

  try {
    const auto gen = read_file(join_path(model_dir, "generation_config.json"));
    extract_int(gen, "eos_token_id", t.eos_token_id);
    extract_int(gen, "pad_token_id", t.pad_token_id);
    extract_int(gen, "decoder_start_token_id", t.decoder_start_token_id);
    extract_int(gen, "forced_eos_token_id", t.forced_eos_token_id);
  } catch (...) {
  }

  try {
    const auto cfg = read_file(join_path(model_dir, "config.json"));
    extract_int(cfg, "eos_token_id", t.eos_token_id);
    extract_int(cfg, "pad_token_id", t.pad_token_id);
    extract_int(cfg, "decoder_start_token_id", t.decoder_start_token_id);
    extract_int(cfg, "forced_eos_token_id", t.forced_eos_token_id);
  } catch (...) {
  }

  if (t.forced_eos_token_id == 0 && t.eos_token_id != 0) {
    t.forced_eos_token_id = t.eos_token_id;
  }
  return t;
}

}  // namespace marian_onnx
