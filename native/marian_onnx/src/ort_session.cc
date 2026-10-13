#include "marian_onnx/ort_session.h"

#include <algorithm>
#include <cstring>
#include <fstream>
#include <map>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include <onnxruntime_cxx_api.h>

namespace marian_onnx {
namespace {

Ort::Env& get_ort_env() {
  static Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "marian_onnx");
  return env;
}

std::string join_path(const std::string& dir, const std::string& name) {
  if (dir.empty()) return name;
  const char last = dir.back();
  if (last == '/' || last == '\\') return dir + name;
  return dir + "/" + name;
}

bool file_exists(const std::string& path) {
  std::ifstream f(path, std::ios::binary);
  return f.good();
}

Ort::Value clone_float_tensor(OrtAllocator* alloc, const Ort::Value& v) {
  if (!v) return Ort::Value{nullptr};
  auto info = v.GetTensorTypeAndShapeInfo();
  auto shape = info.GetShape();
  const size_t count = info.GetElementCount();
  const float* src = v.GetTensorData<float>();
  if (!src && count > 0) return Ort::Value{nullptr};
  auto copy =
      Ort::Value::CreateTensor<float>(alloc, shape.data(), shape.size());
  if (count > 0) {
    std::memcpy(copy.GetTensorMutableData<float>(), src, count * sizeof(float));
  }
  return copy;
}

Ort::Value make_empty_float_tensor(OrtAllocator* alloc,
                                   const std::vector<int64_t>& shape) {
  return Ort::Value::CreateTensor<float>(alloc, shape.data(), shape.size());
}

Ort::Value make_bool_tensor(OrtAllocator* alloc, bool value) {
  const int64_t shape[] = {1};
  auto tensor = Ort::Value::CreateTensor<bool>(alloc, shape, 1);
  *tensor.GetTensorMutableData<bool>() = value;
  return tensor;
}

Ort::Value make_int64_tensor(OrtAllocator* alloc,
                             const std::vector<int64_t>& data,
                             const std::vector<int64_t>& shape) {
  // Allocate via ORT allocator so lifetime is tied to the Ort::Value.
  auto tensor =
      Ort::Value::CreateTensor<int64_t>(alloc, shape.data(), shape.size());
  std::memcpy(tensor.GetTensorMutableData<int64_t>(), data.data(),
              data.size() * sizeof(int64_t));
  return tensor;
}

std::string present_to_past_name(const std::string& present) {
  const std::string from = "present.";
  if (present.compare(0, from.size(), from) == 0) {
    return "past_key_values." + present.substr(from.size());
  }
  return present;
}

struct OrtPast final : PastKeyValues {
  explicit OrtPast(OrtAllocator* alloc,
                   std::map<std::string, Ort::Value> by_name, int length)
      : alloc_(alloc), by_name_(std::move(by_name)), length_(length) {}

  int past_length() const override { return length_; }

  std::unique_ptr<PastKeyValues> clone() const override {
    std::map<std::string, Ort::Value> copies;
    for (const auto& [k, v] : by_name_) {
      copies.emplace(k, clone_float_tensor(alloc_, v));
    }
    return std::make_unique<OrtPast>(alloc_, std::move(copies), length_);
  }

  OrtAllocator* alloc_;
  std::map<std::string, Ort::Value> by_name_;
  int length_;
};

struct OrtEncoderOwned final : EncoderStates {
  OrtEncoderOwned(Ort::Value hidden, std::vector<int64_t> mask, int seq)
      : hidden_states(std::move(hidden)),
        attention_mask(std::move(mask)),
        seq_len(seq) {}

  Ort::Value hidden_states{nullptr};
  std::vector<int64_t> attention_mask;
  int seq_len;
};

class OrtMarianSession final : public Seq2SeqSession {
 public:
  std::unique_ptr<Ort::Session> create_session(const std::string& path) {
    Ort::SessionOptions opts;
    opts.SetIntraOpNumThreads(2);
    // Disable CPU memory arena on mobile so large model buffers are freed
    // immediately on session destruction instead of retained in the pool.
    opts.DisableCpuMemArena();
    opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
#ifdef _WIN32
    const std::wstring wpath(path.begin(), path.end());
    return std::make_unique<Ort::Session>(get_ort_env(), wpath.c_str(), opts);
#else
    return std::make_unique<Ort::Session>(get_ort_env(), path.c_str(), opts);
#endif
  }

  explicit OrtMarianSession(const std::string& model_dir)
      : model_dir_(model_dir),
        memory_info_(Ort::MemoryInfo::CreateCpu(OrtDeviceAllocator,
                                                OrtMemTypeDefault)) {
    const auto enc_path = join_path(model_dir, "encoder_model.onnx");
    const auto merged_path = join_path(model_dir, "decoder_model_merged.onnx");
    has_merged_decoder_ = file_exists(merged_path);
    encoder_ = create_session(enc_path);
    if (has_merged_decoder_) {
      // With a single merged decoder (~18-88 MB quantized), keep both
      // encoder_ and decoder_merged_ resident in RAM on all platforms.
      decoder_merged_ = create_session(merged_path);
      discover_merged_io();
      if (merged_presents_.empty()) {
        throw std::runtime_error(
            "decoder_model_merged.onnx does not emit present KV tensors");
      }
      vocab_size_ = read_vocab_size_from_session(*decoder_merged_);
    } else {
#ifndef __ANDROID__
      const auto dec_path = join_path(model_dir, "decoder_model.onnx");
      const auto past_path =
          join_path(model_dir, "decoder_with_past_model.onnx");
      decoder_ = create_session(dec_path);
      discover_decoder_io();
      if (present_names_.empty()) {
        throw std::runtime_error(
            "decoder_model.onnx does not emit present KV tensors; "
            "re-export with Optimum ORTModelForSeq2SeqLM");
      }
      vocab_size_ = read_vocab_size_from_session(*decoder_);
      decoder_with_past_ = create_session(past_path);
      discover_with_past_io();
#endif
    }
  }

  int vocab_size() const override { return vocab_size_; }

  std::unique_ptr<EncoderStates> encode(
      const std::vector<int32_t>& input_ids) override {
    if (!encoder_) {
      encoder_ = create_session(join_path(model_dir_, "encoder_model.onnx"));
    }
    const int64_t seq = static_cast<int64_t>(input_ids.size());
    std::vector<int64_t> ids(input_ids.begin(), input_ids.end());
    std::vector<int64_t> mask(input_ids.size(), 1);
    std::vector<int64_t> shape = {1, seq};

    OrtAllocator* alloc = static_cast<OrtAllocator*>(allocator_);
    Ort::Value ids_t = make_int64_tensor(alloc, ids, shape);
    Ort::Value mask_t = make_int64_tensor(alloc, mask, shape);

    const char* input_names[] = {"input_ids", "attention_mask"};
    const char* output_names[] = {"last_hidden_state"};
    Ort::Value inputs[] = {std::move(ids_t), std::move(mask_t)};

    auto outputs = encoder_->Run(Ort::RunOptions{nullptr}, input_names, inputs,
                                 2, output_names, 1);

#ifdef __ANDROID__
    // Only free encoder_ when using legacy split decoders (~925 MB FP32).
    // When using decoder_model_merged.onnx (~140 MB quantized total), keep
    // encoder_ resident for subsequent sentences.
    if (!has_merged_decoder_) {
      encoder_.reset();
    }
#endif

    if (outputs.empty() || !outputs[0]) {
      throw std::runtime_error("encoder Run returned null output");
    }

    return std::make_unique<OrtEncoderOwned>(
        std::move(outputs[0]), std::move(mask), static_cast<int>(seq));
  }

  std::pair<Logits, std::unique_ptr<PastKeyValues>> decode_step(
      int32_t token_id,
      const EncoderStates& encoder,
      PastKeyValues* past,
      int /*start_pos*/) override {
    const auto* enc = static_cast<const OrtEncoderOwned*>(&encoder);
    if (!enc) throw std::runtime_error("invalid encoder state");

    std::vector<int64_t> ids = {static_cast<int64_t>(token_id)};
    std::vector<int64_t> id_shape = {1, 1};
    OrtAllocator* alloc = static_cast<OrtAllocator*>(allocator_);
    Ort::Value ids_t = make_int64_tensor(alloc, ids, id_shape);

    std::vector<int64_t> mask_shape = {
        1, static_cast<int64_t>(enc->attention_mask.size())};
    Ort::Value mask_t =
        make_int64_tensor(alloc, enc->attention_mask, mask_shape);

    if (has_merged_decoder_) {
      auto* ort_past =
          past == nullptr ? nullptr : static_cast<OrtPast*>(past);
      return run_decoder_merged(std::move(ids_t), std::move(mask_t), *enc,
                                ort_past);
    }

    if (past == nullptr) {
      if (!enc->hidden_states) {
        throw std::runtime_error("encoder hidden_states is null");
      }
      Ort::Value hidden = clone_float_tensor(alloc, enc->hidden_states);
      return run_decoder(std::move(ids_t), std::move(mask_t),
                         std::move(hidden));
    }
    auto* ort_past = static_cast<OrtPast*>(past);
    return run_decoder_with_past(std::move(ids_t), std::move(mask_t), *enc,
                                 *ort_past);
  }

 private:
  void discover_merged_io() {
    merged_inputs_.clear();
    merged_presents_.clear();
    OrtAllocator* alloc = static_cast<OrtAllocator*>(allocator_);

    const size_t n_in = decoder_merged_->GetInputCount();
    for (size_t i = 0; i < n_in; ++i) {
      auto name = decoder_merged_->GetInputNameAllocated(i, alloc);
      const std::string s = name.get();
      merged_inputs_.push_back(s);
      if (s.find("past_key_values") != std::string::npos &&
          past_num_heads_ == 0) {
        auto info = decoder_merged_->GetInputTypeInfo(i);
        auto shape = info.GetTensorTypeAndShapeInfo().GetShape();
        if (shape.size() == 4 && shape[1] > 0 && shape[3] > 0) {
          past_num_heads_ = shape[1];
          past_head_dim_ = shape[3];
        }
      }
    }
    if (past_num_heads_ <= 0) past_num_heads_ = 8;
    if (past_head_dim_ <= 0) past_head_dim_ = 64;

    const size_t n_out = decoder_merged_->GetOutputCount();
    for (size_t i = 0; i < n_out; ++i) {
      auto name = decoder_merged_->GetOutputNameAllocated(i, alloc);
      const std::string s = name.get();
      if (s.find("present") != std::string::npos) {
        merged_presents_.push_back(s);
      } else if (s == "logits") {
        logits_name_ = s;
      }
    }
    std::sort(merged_presents_.begin(), merged_presents_.end());
  }

  void discover_decoder_io() {
    present_names_.clear();
    OrtAllocator* alloc = static_cast<OrtAllocator*>(allocator_);
    const size_t n_out = decoder_->GetOutputCount();
    for (size_t i = 0; i < n_out; ++i) {
      auto name = decoder_->GetOutputNameAllocated(i, alloc);
      const std::string s = name.get();
      if (s.find("present") != std::string::npos) {
        present_names_.push_back(s);
      } else if (s == "logits") {
        logits_name_ = s;
      }
    }
    std::sort(present_names_.begin(), present_names_.end());
  }

  void discover_with_past_io() {
    past_input_names_.clear();
    with_past_inputs_.clear();
    with_past_presents_.clear();

    OrtAllocator* alloc = static_cast<OrtAllocator*>(allocator_);

    const size_t n_in = decoder_with_past_->GetInputCount();
    for (size_t i = 0; i < n_in; ++i) {
      auto name = decoder_with_past_->GetInputNameAllocated(i, alloc);
      const std::string s = name.get();
      with_past_inputs_.push_back(s);
      if (s.find("past_key_values") != std::string::npos) {
        past_input_names_.push_back(s);
      }
    }
    std::sort(past_input_names_.begin(), past_input_names_.end());

    const size_t n_out_wp = decoder_with_past_->GetOutputCount();
    for (size_t i = 0; i < n_out_wp; ++i) {
      auto name = decoder_with_past_->GetOutputNameAllocated(i, alloc);
      const std::string s = name.get();
      if (s.find("present") != std::string::npos) {
        with_past_presents_.push_back(s);
      }
    }
    std::sort(with_past_presents_.begin(), with_past_presents_.end());
  }

  int read_vocab_size_from_session(Ort::Session& sess) {
    // Find index of logits output
    OrtAllocator* alloc = static_cast<OrtAllocator*>(allocator_);
    const size_t n_out = sess.GetOutputCount();
    for (size_t i = 0; i < n_out; ++i) {
      auto name = sess.GetOutputNameAllocated(i, alloc);
      if (std::string(name.get()) == "logits") {
        auto info = sess.GetOutputTypeInfo(i);
        auto tensor = info.GetTensorTypeAndShapeInfo();
        auto shape = tensor.GetShape();
        if (shape.size() >= 3 && shape.back() > 0) {
          return static_cast<int>(shape.back());
        }
      }
    }
    return 65001;
  }

  std::pair<Logits, std::unique_ptr<PastKeyValues>> run_decoder_merged(
      Ort::Value ids,
      Ort::Value mask,
      const OrtEncoderOwned& enc,
      OrtPast* past) {
    if (!decoder_merged_) {
      decoder_merged_ = create_session(
          join_path(model_dir_, "decoder_model_merged.onnx"));
      if (merged_inputs_.empty()) {
        discover_merged_io();
        if (merged_presents_.empty()) {
          throw std::runtime_error(
              "decoder_model_merged.onnx does not emit present KV tensors");
        }
        vocab_size_ = read_vocab_size_from_session(*decoder_merged_);
      }
    }

    OrtAllocator* alloc = static_cast<OrtAllocator*>(allocator_);
    const bool use_cache = past != nullptr;

    std::vector<const char*> in_names;
    std::vector<Ort::Value> in_vals;
    std::vector<std::string> moved_past_keys;
    std::vector<size_t> moved_past_indices;
    in_names.reserve(merged_inputs_.size());
    in_vals.reserve(merged_inputs_.size());

    auto hidden_info = enc.hidden_states.GetTensorTypeAndShapeInfo();
    auto hidden_shape = hidden_info.GetShape();
    const int64_t d_model =
        hidden_shape.size() >= 3 ? hidden_shape[2] : 512;

    for (const auto& name : merged_inputs_) {
      if (name == "input_ids") {
        in_names.push_back("input_ids");
        in_vals.push_back(std::move(ids));
      } else if (name == "encoder_attention_mask") {
        in_names.push_back("encoder_attention_mask");
        in_vals.push_back(std::move(mask));
      } else if (name == "encoder_hidden_states") {
        in_names.push_back("encoder_hidden_states");
        if (!use_cache) {
          in_vals.push_back(clone_float_tensor(alloc, enc.hidden_states));
        } else {
          // On cached steps, encoder KVs are already in past_key_values; pass
          // a 0-length tensor so we don't clone encoder_hidden_states.
          in_vals.push_back(make_empty_float_tensor(alloc, {1, 0, d_model}));
        }
      } else if (name == "use_cache_branch") {
        in_names.push_back("use_cache_branch");
        in_vals.push_back(make_bool_tensor(alloc, use_cache));
      } else {
        if (!use_cache) {
          in_names.push_back(name.c_str());
          in_vals.push_back(make_empty_float_tensor(
              alloc, {1, past_num_heads_, 0, past_head_dim_}));
        } else {
          auto it = past->by_name_.find(name);
          if (it != past->by_name_.end()) {
            in_names.push_back(it->first.c_str());
            moved_past_keys.push_back(it->first);
            moved_past_indices.push_back(in_vals.size());
            in_vals.push_back(std::move(it->second));
          }
        }
      }
    }

    std::vector<const char*> out_names;
    out_names.push_back(logits_name_.c_str());
    for (auto& n : merged_presents_) out_names.push_back(n.c_str());

    auto outputs = decoder_merged_->Run(
        Ort::RunOptions{nullptr}, in_names.data(), in_vals.data(),
        in_vals.size(), out_names.data(), out_names.size());

    Logits logits = extract_last_logits(outputs[0]);
    std::map<std::string, Ort::Value> next;
    if (!use_cache) {
      for (size_t i = 1; i < outputs.size(); ++i) {
        next.emplace(present_to_past_name(merged_presents_[i - 1]),
                     std::move(outputs[i]));
      }
      return {std::move(logits),
              std::make_unique<OrtPast>(alloc, std::move(next), 1)};
    }

    for (size_t i = 0; i < moved_past_keys.size(); ++i) {
      next.emplace(std::move(moved_past_keys[i]),
                   std::move(in_vals[moved_past_indices[i]]));
    }
    for (size_t i = 1; i < outputs.size(); ++i) {
      const std::string& p_name = merged_presents_[i - 1];
      // When use_cache_branch=true, encoder present outputs are dummy 0-batch
      // tensors; keep the step-0 encoder KVs already in `next`.
      if (p_name.find(".encoder.") != std::string::npos) {
        continue;
      }
      next.insert_or_assign(present_to_past_name(p_name),
                            std::move(outputs[i]));
    }
    return {std::move(logits),
            std::make_unique<OrtPast>(alloc, std::move(next),
                                      past->length_ + 1)};
  }

  std::pair<Logits, std::unique_ptr<PastKeyValues>> run_decoder(
      Ort::Value ids,
      Ort::Value mask,
      Ort::Value hidden) {
    if (!ids) throw std::runtime_error("run_decoder: ids is null");
    if (!mask) throw std::runtime_error("run_decoder: mask is null");
    if (!hidden) throw std::runtime_error("run_decoder: hidden is null");

#ifdef __ANDROID__
    decoder_with_past_.reset();
#endif
    if (!decoder_) {
      decoder_ = create_session(join_path(model_dir_, "decoder_model.onnx"));
      if (present_names_.empty()) {
        discover_decoder_io();
        if (present_names_.empty()) {
          throw std::runtime_error(
              "decoder_model.onnx does not emit present KV tensors; "
              "re-export with Optimum ORTModelForSeq2SeqLM");
        }
        vocab_size_ = read_vocab_size_from_session(*decoder_);
      }
    }

    std::vector<const char*> in_names = {
        "input_ids", "encoder_attention_mask", "encoder_hidden_states"};
    std::vector<Ort::Value> in_vals;
    in_vals.push_back(std::move(ids));
    in_vals.push_back(std::move(mask));
    in_vals.push_back(std::move(hidden));

    std::vector<const char*> out_names;
    out_names.push_back(logits_name_.c_str());
    for (auto& n : present_names_) out_names.push_back(n.c_str());

    auto outputs = decoder_->Run(Ort::RunOptions{nullptr}, in_names.data(),
                                 in_vals.data(), in_vals.size(),
                                 out_names.data(), out_names.size());

#ifdef __ANDROID__
    // Step 0 only runs once per utterance; free its ~365 MB session before
    // loading decoder_with_past_ (~352 MB) on step 1.
    decoder_.reset();
#endif

    Logits logits = extract_last_logits(outputs[0]);
    std::map<std::string, Ort::Value> past_map;
    for (size_t i = 1; i < outputs.size(); ++i) {
      past_map.emplace(present_to_past_name(present_names_[i - 1]),
                       std::move(outputs[i]));
    }
    return {std::move(logits),
            std::make_unique<OrtPast>(static_cast<OrtAllocator*>(allocator_),
                                      std::move(past_map), 1)};
  }

  std::pair<Logits, std::unique_ptr<PastKeyValues>> run_decoder_with_past(
      Ort::Value ids,
      Ort::Value mask,
      const OrtEncoderOwned& enc,
      OrtPast& past) {
    if (!decoder_with_past_) {
      decoder_with_past_ = create_session(
          join_path(model_dir_, "decoder_with_past_model.onnx"));
      if (with_past_inputs_.empty()) {
        discover_with_past_io();
      }
    }
    const bool wants_hidden = std::find(with_past_inputs_.begin(),
                                        with_past_inputs_.end(),
                                        "encoder_hidden_states") !=
                              with_past_inputs_.end();

    std::vector<const char*> in_names;
    std::vector<Ort::Value> in_vals;
    std::vector<std::string> moved_past_keys;
    std::vector<size_t> moved_past_indices;
    in_names.reserve(with_past_inputs_.size());
    in_vals.reserve(with_past_inputs_.size());

    // Maintain a consistent order based on discovered input names.
    // Move past KV tensors into in_vals instead of cloning (decode_step
    // consumes `past`; beam forking already clones via OrtPast::clone()).
    for (const auto& name : with_past_inputs_) {
      if (name == "input_ids") {
        in_names.push_back("input_ids");
        in_vals.push_back(std::move(ids));
      } else if (name == "encoder_attention_mask") {
        in_names.push_back("encoder_attention_mask");
        in_vals.push_back(std::move(mask));
      } else if (name == "encoder_hidden_states") {
        if (wants_hidden) {
          in_names.push_back("encoder_hidden_states");
          in_vals.push_back(clone_float_tensor(
              static_cast<OrtAllocator*>(allocator_), enc.hidden_states));
        }
      } else {
        auto it = past.by_name_.find(name);
        if (it != past.by_name_.end()) {
          in_names.push_back(it->first.c_str());
          moved_past_keys.push_back(it->first);
          moved_past_indices.push_back(in_vals.size());
          in_vals.push_back(std::move(it->second));
        }
      }
    }

    std::vector<const char*> out_names;
    out_names.push_back("logits");
    for (auto& n : with_past_presents_) out_names.push_back(n.c_str());

    auto outputs = decoder_with_past_->Run(
        Ort::RunOptions{nullptr}, in_names.data(), in_vals.data(),
        in_vals.size(), out_names.data(), out_names.size());

    Logits logits = extract_last_logits(outputs[0]);

    // Move unchanged encoder KV tensors back from in_vals and overwrite
    // decoder KV tensors with the new outputs — zero tensor clones per step.
    std::map<std::string, Ort::Value> next;
    for (size_t i = 0; i < moved_past_keys.size(); ++i) {
      next.emplace(std::move(moved_past_keys[i]),
                   std::move(in_vals[moved_past_indices[i]]));
    }
    for (size_t i = 1; i < outputs.size(); ++i) {
      next.insert_or_assign(present_to_past_name(with_past_presents_[i - 1]),
                            std::move(outputs[i]));
    }
    return {std::move(logits),
            std::make_unique<OrtPast>(static_cast<OrtAllocator*>(allocator_),
                                      std::move(next), past.length_ + 1)};
  }

  Logits extract_last_logits(Ort::Value& logits_v) {
    auto info = logits_v.GetTensorTypeAndShapeInfo();
    auto shape = info.GetShape();
    if (shape.size() != 3) {
      throw std::runtime_error("logits rank != 3");
    }
    const int64_t batch = shape[0];
    const int64_t seq = shape[1];
    const int64_t vocab = shape[2];
    
    if (seq <= 0 || vocab <= 0) {
      throw std::runtime_error("invalid logits shape");
    }

    const float* data = logits_v.GetTensorData<float>();
    // We only care about the last token's logits
    const float* row = data + (seq - 1) * vocab;
    Logits out(static_cast<size_t>(vocab));
    std::memcpy(out.data(), row, static_cast<size_t>(vocab) * sizeof(float));
    vocab_size_ = static_cast<int>(vocab);
    return out;
  }

  std::string model_dir_;
  bool has_merged_decoder_ = false;
  int64_t past_num_heads_ = 0;
  int64_t past_head_dim_ = 0;
  Ort::MemoryInfo memory_info_;
  Ort::AllocatorWithDefaultOptions allocator_;
  std::unique_ptr<Ort::Session> encoder_;
  std::unique_ptr<Ort::Session> decoder_;
  std::unique_ptr<Ort::Session> decoder_with_past_;
  std::unique_ptr<Ort::Session> decoder_merged_;
  std::string logits_name_ = "logits";
  std::vector<std::string> present_names_;
  std::vector<std::string> past_input_names_;
  std::vector<std::string> with_past_inputs_;
  std::vector<std::string> with_past_presents_;
  std::vector<std::string> merged_inputs_;
  std::vector<std::string> merged_presents_;
  int vocab_size_ = 65001;
};

}  // namespace

std::unique_ptr<Seq2SeqSession> load_ort_session(const std::string& model_dir) {
  return std::make_unique<OrtMarianSession>(model_dir);
}

}  // namespace marian_onnx
