#include "marian_onnx/decode.h"
#include "marian_onnx/fake_session.h"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

int g_failures = 0;

void expect_true(bool cond, const char* msg) {
  if (!cond) {
    std::cerr << "FAIL: " << msg << "\n";
    ++g_failures;
  }
}

void expect_eq_int(int a, int b, const char* msg) {
  if (a != b) {
    std::cerr << "FAIL: " << msg << " (got " << a << ", want " << b << ")\n";
    ++g_failures;
  }
}

marian_onnx::Logits one_hot_best(int vocab, int best) {
  marian_onnx::Logits logits(vocab, -10.0f);
  logits[best] = 10.0f;
  return logits;
}

marian_onnx::SpecialTokens tokens() {
  marian_onnx::SpecialTokens s;
  s.pad_token_id = 0;
  s.eos_token_id = 2;
  s.decoder_start_token_id = 0;
  s.forced_eos_token_id = 2;
  s.unk_token_id = 1;
  return s;
}

  void test_encoder_once_and_length_one_steps() {
  constexpr int kVocab = 8;
  // Scripted path: start -> 3 -> 4 -> eos(2)
  auto fn = [=](int step, int32_t /*token*/, int /*past*/) {
    if (step == 0) return one_hot_best(kVocab, 3);
    if (step == 1) return one_hot_best(kVocab, 4);
    return one_hot_best(kVocab, 2);
  };
  marian_onnx::FakeSession session(kVocab, fn);
  marian_onnx::TranslationConfig cfg;
  cfg.num_beams = 1;
  cfg.max_new_tokens = 16;
  cfg.no_repeat_ngram_size = 0;

  auto out = marian_onnx::generate(session, {10, 11, 2}, tokens(), cfg);

  expect_eq_int(session.encode_calls, 1, "encoder called once");
  expect_true(!session.decode_input_lengths.empty(), "had decode steps");
  for (int len : session.decode_input_lengths) {
    expect_eq_int(len, 1, "every decode input length is 1");
  }
  expect_true(out.size() >= 2, "produced tokens including start");
  expect_eq_int(out.front(), 0, "starts with decoder_start");
  expect_eq_int(out[1], 3, "first generated id");
  expect_eq_int(out[2], 4, "second generated id");
  expect_eq_int(out.back(), 2, "ends with eos");
}

void test_past_length_grows_with_step() {
  constexpr int kVocab = 6;
  auto fn = [=](int step, int32_t /*token*/, int /*past*/) {
    // Never emit eos until max; force past growth check over 4 steps.
    return one_hot_best(kVocab, 3);
  };
  marian_onnx::FakeSession session(kVocab, fn);
  marian_onnx::TranslationConfig cfg;
  cfg.num_beams = 1;
  cfg.max_new_tokens = 4;
  cfg.no_repeat_ngram_size = 0;
  marian_onnx::SpecialTokens sp = tokens();
  sp.eos_token_id = 99;  // unreachable
  sp.forced_eos_token_id = 99;

  marian_onnx::generate(session, {1, 2}, sp, cfg);

  expect_eq_int(static_cast<int>(session.past_lengths_seen.size()), 4,
                "four decode steps");
  for (int k = 0; k < 4; ++k) {
    expect_eq_int(session.past_lengths_seen[k], k,
                  "past length on step k equals k");
  }
}

void test_eos_stops_early() {
  constexpr int kVocab = 5;
  auto fn = [=](int step, int32_t /*token*/, int /*past*/) {
    if (step == 0) return one_hot_best(kVocab, 3);
    return one_hot_best(kVocab, 2);  // eos
  };
  marian_onnx::FakeSession session(kVocab, fn);
  marian_onnx::TranslationConfig cfg;
  cfg.num_beams = 1;
  cfg.max_new_tokens = 50;
  cfg.no_repeat_ngram_size = 0;

  auto out = marian_onnx::generate(session, {7}, tokens(), cfg);
  expect_eq_int(static_cast<int>(session.tokens_seen.size()), 2,
                "stops after eos");
  expect_eq_int(out.back(), 2, "last token is eos");
}

void test_ngram_bans_token() {
  constexpr int kVocab = 10;
  // Always prefer 5 over 4. After [bos,5,5], ngram=2 sees prefix [5] and the
  // prior bigram [5,5], so 5 is banned and we take 4.
  auto fn = [=](int /*step*/, int32_t /*token*/, int /*past*/) {
    marian_onnx::Logits logits(kVocab, -20.0f);
    logits[5] = 5.0f;
    logits[4] = 4.0f;
    logits[2] = -1.0f;
    return logits;
  };
  marian_onnx::FakeSession session(kVocab, fn);
  marian_onnx::TranslationConfig cfg;
  cfg.num_beams = 1;
  cfg.max_new_tokens = 3;
  cfg.no_repeat_ngram_size = 2;
  marian_onnx::SpecialTokens sp = tokens();
  sp.eos_token_id = 99;
  sp.forced_eos_token_id = 99;

  auto out = marian_onnx::generate(session, {1}, sp, cfg);
  expect_true(out.size() >= 4, "bos + 3 generated");
  expect_eq_int(out[1], 5, "first pick is 5");
  expect_eq_int(out[2], 5, "second pick still 5");
  expect_eq_int(out[3], 4, "ngram bans 5 so third is 4");
}

void test_beam_forks_past_and_length_penalty() {
  constexpr int kVocab = 8;
  // Step 0: top-2 are 3 (strong) and 4 (weak). Beam 3 finishes next step;
  // beam 4 continues then finishes. Strong first token + length_penalty make
  // the short hyp win. Multiple length-1 steps with growing past prove the
  // per-beam KV fork (move + clone) path ran.
  auto fn = [=](int /*step*/, int32_t token, int past) {
    marian_onnx::Logits logits(kVocab, -30.0f);
    if (past == 0) {
      logits[3] = 8.0f;
      logits[4] = 0.0f;
      return logits;
    }
    if (token == 3) {
      logits[2] = 5.0f;
      return logits;
    }
    if (token == 4) {
      logits[5] = 5.0f;
      return logits;
    }
    if (token == 5) {
      logits[2] = 5.0f;
      return logits;
    }
    logits[2] = 1.0f;
    return logits;
  };
  marian_onnx::FakeSession session(kVocab, fn);
  marian_onnx::TranslationConfig cfg;
  cfg.num_beams = 2;
  cfg.max_new_tokens = 8;
  cfg.length_penalty = 1.2;
  cfg.no_repeat_ngram_size = 0;

  auto out = marian_onnx::generate(session, {9, 8}, tokens(), cfg);

  expect_eq_int(session.encode_calls, 1, "beam: encoder once");
  for (int len : session.decode_input_lengths) {
    expect_eq_int(len, 1, "beam: length-1 decode inputs");
  }
  expect_true(static_cast<int>(session.past_lengths_seen.size()) >= 3,
              "beam expanded more than one hypothesis");
  expect_eq_int(session.past_lengths_seen.front(), 0, "first past is 0");
  // After forking, at least one step sees past_length == 1.
  bool saw_past1 = false;
  for (int p : session.past_lengths_seen) {
    if (p == 1) saw_past1 = true;
  }
  expect_true(saw_past1, "forked beams decode with past_length 1");
  expect_true(out.size() >= 2, "beam produced tokens");
  expect_eq_int(out[1], 3, "strong short beam wins");
  expect_eq_int(out.back(), 2, "beam ends with eos");
}

void test_beam_early_stops_when_finished_beats_active() {
  constexpr int kVocab = 8;
  // Step 0: beam 0 picks token 3 (log_p ≈ 0) and token 4 (log_p ≈ -8).
  // Step 1: beam [0,3] emits eos(2) with log_p ≈ 0 -> finished score ≈ 0.
  //         beam [0,4] never emits eos, only token 5 with log_p ≈ 0 -> score ≈ -8.
  // Even with max_new_tokens = 128, beam search must stop early once the best
  // finished hypothesis is better than the best possible extension of active
  // beams, instead of running all 128 steps.
  auto fn = [=](int /*step*/, int32_t token, int past) {
    marian_onnx::Logits logits(kVocab, -30.0f);
    if (past == 0) {
      logits[3] = 8.0f;
      logits[4] = 0.0f;
      return logits;
    }
    if (token == 3) {
      logits[2] = 10.0f;  // eos
      logits[5] = 2.0f;
      return logits;
    }
    // Unfinished beams never emit eos (2), only 5 or 6.
    logits[5] = 8.0f;
    logits[6] = 7.0f;
    return logits;
  };
  marian_onnx::FakeSession session(kVocab, fn);
  marian_onnx::TranslationConfig cfg;
  cfg.num_beams = 2;
  cfg.max_new_tokens = 128;
  cfg.length_penalty = 1.2;
  cfg.no_repeat_ngram_size = 0;

  auto out = marian_onnx::generate(session, {9, 8}, tokens(), cfg);

  // Without early stopping, decode_step runs ~255 times (1 + 2*127).
  // With early stopping, it should finish in <= 10 decode_step calls.
  expect_true(static_cast<int>(session.past_lengths_seen.size()) <= 10,
              "beam search stops early instead of running all 128 steps");
  expect_eq_int(out[1], 3, "early-stopped beam picks best hypothesis");
  expect_eq_int(out.back(), 2, "early-stopped beam ends with eos");
}

void test_helpers() {
  expect_true(std::abs(marian_onnx::normalized_score(0.0f, 1, 1.0) - 0.0f) <
                  1e-5f,
              "norm score zero");
  std::vector<float> scores = {1.0f, 3.0f, 2.0f};
  expect_eq_int(marian_onnx::argmax(scores), 1, "argmax");
  auto top = marian_onnx::top_k_indices(scores, 2);
  expect_eq_int(static_cast<int>(top.size()), 2, "top_k size");
  expect_eq_int(top[0], 1, "top1 id");

  std::vector<int32_t> toks = {0, 5, 5};
  std::vector<float> ban_scores(10, 0.0f);
  marian_onnx::apply_no_repeat_ngram(toks, ban_scores, 2);
  expect_true(ban_scores[5] == -std::numeric_limits<float>::infinity(),
              "ngram sets -inf");
}

}  // namespace

int main() {
  test_helpers();
  test_encoder_once_and_length_one_steps();
  test_past_length_grows_with_step();
  test_eos_stops_early();
  test_ngram_bans_token();
  test_beam_forks_past_and_length_penalty();
  test_beam_early_stops_when_finished_beats_active();

  if (g_failures != 0) {
    std::cerr << g_failures << " assertion(s) failed\n";
    return 1;
  }
  std::cout << "All decode tests passed\n";
  return 0;
}
