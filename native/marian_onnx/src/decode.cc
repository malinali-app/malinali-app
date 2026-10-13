#include "marian_onnx/decode.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <utility>

namespace marian_onnx {
namespace {

struct Beam {
  std::vector<int32_t> tokens;
  float score = 0.0f;
  bool finished = false;
  std::unique_ptr<PastKeyValues> past;
};

struct ExpandedParent {
  std::vector<int32_t> tokens;
  float score = 0.0f;
  std::unique_ptr<PastKeyValues> past;
  std::vector<std::pair<int32_t, float>> next;  // token, log_p
};

struct BeamCand {
  size_t parent_idx = 0;
  std::vector<int32_t> tokens;
  float score = 0.0f;
  bool finished = false;
};

std::vector<int32_t> greedy_decode(Seq2SeqSession& session,
                                   const EncoderStates& encoder,
                                   const SpecialTokens& special,
                                   const TranslationConfig& cfg) {
  std::vector<int32_t> token_ids = {special.decoder_start_token_id};
  std::unique_ptr<PastKeyValues> past;
  const int max_new = cfg.max_new_tokens;

  for (int index = 0; index < max_new; ++index) {
    const int32_t feed = token_ids.back();
    const int start_pos = past == nullptr ? 0 : past->past_length();
    auto [logits, present] =
        session.decode_step(feed, encoder, past.get(), start_pos);
    apply_no_repeat_ngram(token_ids, logits, cfg.no_repeat_ngram_size);
    const int next = argmax(logits);
    token_ids.push_back(static_cast<int32_t>(next));
    past = std::move(present);
    if (next == special.eos_token_id || next == special.forced_eos_token_id) {
      break;
    }
  }
  return token_ids;
}

std::vector<int32_t> beam_search_incremental(Seq2SeqSession& session,
                                             const EncoderStates& encoder,
                                             const SpecialTokens& special,
                                             const TranslationConfig& cfg) {
  const int num_beams = cfg.num_beams;
  const int max_new = cfg.max_new_tokens;
  const double length_penalty = cfg.length_penalty;
  const int ngram = cfg.no_repeat_ngram_size;
  const int32_t eos = special.eos_token_id;
  const int32_t forced_eos = special.forced_eos_token_id;
  const int32_t bos = special.decoder_start_token_id;

  std::vector<Beam> beams;
  beams.push_back(Beam{std::vector<int32_t>{bos}, 0.0f, false, nullptr});
  std::vector<Beam> finished;

  for (int step = 0; step < max_new; ++step) {
    std::vector<ExpandedParent> parents;

    for (size_t b_idx = 0; b_idx < beams.size(); ++b_idx) {
      auto& beam = beams[b_idx];
      if (beam.finished) {
        finished.push_back(std::move(beam));
        continue;
      }
      const int32_t feed = beam.tokens.back();
      const int start_pos =
          beam.past == nullptr ? 0 : beam.past->past_length();

      auto [logits, present] =
          session.decode_step(feed, encoder, beam.past.get(), start_pos);

      if (!present) {
        throw std::runtime_error("decode_step returned null present");
      }

      apply_no_repeat_ngram(beam.tokens, logits, ngram);
      log_softmax_inplace(logits);

      std::vector<std::pair<int32_t, float>> next;
      for (int idx : top_k_indices(logits, num_beams)) {
        next.emplace_back(static_cast<int32_t>(idx), logits[idx]);
      }

      parents.push_back(ExpandedParent{
          std::move(beam.tokens),
          beam.score,
          std::move(present),
          std::move(next),
      });
    }
    beams.clear();

    std::vector<BeamCand> candidates;
    for (size_t parent_idx = 0; parent_idx < parents.size(); ++parent_idx) {
      const auto& parent = parents[parent_idx];
      for (const auto& [token, log_p] : parent.next) {
        auto toks = parent.tokens;
        toks.push_back(token);
        const bool done = token == eos || token == forced_eos;
        candidates.push_back(
            BeamCand{parent_idx, std::move(toks), parent.score + log_p, done});
      }
    }

    // Descending: higher normalized score first.
    std::sort(candidates.begin(), candidates.end(),
              [length_penalty](const BeamCand& a, const BeamCand& b) {
                float sa = normalized_score(a.score, static_cast<int>(a.tokens.size()), length_penalty);
                float sb = normalized_score(b.score, static_cast<int>(b.tokens.size()), length_penalty);
                return sa > sb;
              });

    std::vector<int> parent_use_count(parents.size(), 0);
    int selected_beams = 0;
    int selected_finished = static_cast<int>(finished.size());
    for (const auto& cand : candidates) {
      if (cand.finished) {
        selected_finished++;
      } else if (selected_beams < num_beams) {
        parent_use_count[cand.parent_idx]++;
        selected_beams++;
      }
      if (selected_beams >= num_beams && selected_finished >= num_beams) {
        break;
      }
    }

    for (const auto& cand : candidates) {
      if (cand.finished) {
        finished.push_back(
            Beam{cand.tokens, cand.score, true, nullptr});
      } else if (static_cast<int>(beams.size()) < num_beams) {
        // Optimization: move if it's the last time we use this parent.
        std::unique_ptr<PastKeyValues> p;
        if (parent_use_count[cand.parent_idx] == 1) {
          p = std::move(parents[cand.parent_idx].past);
          parent_use_count[cand.parent_idx] = 0;
        } else {
          p = parents[cand.parent_idx].past->clone();
          parent_use_count[cand.parent_idx]--;
        }
        beams.push_back(
            Beam{cand.tokens, cand.score, false, std::move(p)});
      }
      if (static_cast<int>(beams.size()) >= num_beams &&
          static_cast<int>(finished.size()) >= num_beams) {
        break;
      }
    }

    if (beams.empty()) {
      break;
    }

    // Early stopping (HuggingFace BeamSearchScorer): if we have at least one
    // finished hypothesis and the best finished normalized score is >= the
    // highest possible normalized score an active beam could achieve (since
    // future log_p <= 0, score <= 0, and length penalty norm >= 1.0 when
    // length_penalty >= 0, best possible future score for a beam of current
    // length L is normalized_score(beam.score, L + 1, length_penalty)), stop.
    if (!finished.empty()) {
      float best_finished = -std::numeric_limits<float>::infinity();
      for (const auto& f : finished) {
        const float s = normalized_score(
            f.score, static_cast<int>(f.tokens.size()), length_penalty);
        if (s > best_finished) best_finished = s;
      }
      float best_active = -std::numeric_limits<float>::infinity();
      for (const auto& b : beams) {
        const int cur_len = static_cast<int>(b.tokens.size()) + 1;
        const float s_now = normalized_score(b.score, cur_len, length_penalty);
        const float s_max = normalized_score(
            b.score, std::max(cur_len, max_new + 1), length_penalty);
        const float bound = std::max(s_now, s_max);
        if (bound > best_active) best_active = bound;
      }
      if (best_finished >= best_active ||
          static_cast<int>(finished.size()) >= num_beams * 2) {
        break;
      }
    }
  }


  for (auto& b : beams) {
    finished.push_back(std::move(b));
  }
  std::sort(finished.begin(), finished.end(),
            [length_penalty](const Beam& a, const Beam& b) {
              return normalized_score(a.score,
                                      static_cast<int>(a.tokens.size()),
                                      length_penalty) >
                     normalized_score(b.score,
                                      static_cast<int>(b.tokens.size()),
                                      length_penalty);
            });

  if (finished.empty()) {
    throw std::runtime_error("beam search produced no hypotheses");
  }
  return finished.front().tokens;
}

}  // namespace

float normalized_score(float score, int len, double length_penalty) {
  const double L = static_cast<double>(std::max(len, 1));
  const double norm = std::pow((5.0 + L) / 6.0, length_penalty);
  return static_cast<float>(static_cast<double>(score) / norm);
}

void apply_no_repeat_ngram(const std::vector<int32_t>& tokens,
                           std::vector<float>& scores,
                           int ngram_size) {
  if (ngram_size <= 0 || static_cast<int>(tokens.size()) < ngram_size) {
    return;
  }
  const int prefix_len = ngram_size - 1;
  const int32_t* prefix = tokens.data() + tokens.size() - prefix_len;
  const int last_start =
      static_cast<int>(tokens.size()) - ngram_size;
  for (int start = 0; start <= last_start; ++start) {
    bool match = true;
    for (int i = 0; i < prefix_len; ++i) {
      if (tokens[start + i] != prefix[i]) {
        match = false;
        break;
      }
    }
    if (match) {
      const int banned = static_cast<int>(tokens[start + prefix_len]);
      if (banned >= 0 && banned < static_cast<int>(scores.size())) {
        scores[banned] = -std::numeric_limits<float>::infinity();
      }
    }
  }
}

void log_softmax_inplace(std::vector<float>& scores) {
  float max_v = -std::numeric_limits<float>::infinity();
  for (float s : scores) {
    if (s > max_v) max_v = s;
  }
  float sum = 0.0f;
  for (float& s : scores) {
    s = std::exp(s - max_v);
    sum += s;
  }
  const float log_sum = std::log(sum);
  for (float& s : scores) {
    s = std::log(s) - log_sum;
  }
}

int argmax(const std::vector<float>& scores) {
  int best_i = 0;
  float best_v = -std::numeric_limits<float>::infinity();
  for (int i = 0; i < static_cast<int>(scores.size()); ++i) {
    if (scores[i] > best_v) {
      best_v = scores[i];
      best_i = i;
    }
  }
  return best_i;
}

std::vector<int> top_k_indices(const std::vector<float>& scores, int k) {
  k = std::min(k, static_cast<int>(scores.size()));
  if (k <= 0) return {};
  std::vector<int> idx(scores.size());
  for (int i = 0; i < static_cast<int>(scores.size()); ++i) idx[i] = i;
  std::partial_sort(
      idx.begin(), idx.begin() + k, idx.end(),
      [&scores](int a, int b) { return scores[a] > scores[b]; });
  idx.resize(k);
  return idx;
}

std::vector<int32_t> generate(Seq2SeqSession& session,
                              const std::vector<int32_t>& encoder_input_ids,
                              const SpecialTokens& special,
                              const TranslationConfig& config) {
  auto encoder = session.encode(encoder_input_ids);
  if (config.num_beams <= 1) {
    return greedy_decode(session, *encoder, special, config);
  }
  return beam_search_incremental(session, *encoder, special, config);
}

}  // namespace marian_onnx
