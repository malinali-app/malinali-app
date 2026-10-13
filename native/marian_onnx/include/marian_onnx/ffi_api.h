#pragma once

#include <stdint.h>

#ifdef _WIN32
#ifdef MARIAN_ONNX_EXPORTS
#define MARIAN_ONNX_API __declspec(dllexport)
#else
#define MARIAN_ONNX_API __declspec(dllimport)
#endif
#else
#define MARIAN_ONNX_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque translator handle (0 on failure).
MARIAN_ONNX_API void* marian_onnx_load(const char* model_dir);

/// Translate [text]. Caller must free the returned string with
/// [marian_onnx_string_free]. Returns nullptr on failure.
MARIAN_ONNX_API char* marian_onnx_translate(
    void* handle,
    const char* text,
    int32_t num_beams,
    int32_t max_new_tokens,
    double length_penalty,
    int32_t no_repeat_ngram_size);

MARIAN_ONNX_API void marian_onnx_string_free(char* s);

MARIAN_ONNX_API void marian_onnx_free(void* handle);

/// Last error message (valid until next API call). Never null.
MARIAN_ONNX_API const char* marian_onnx_last_error(void);

#ifdef __cplusplus
}
#endif
