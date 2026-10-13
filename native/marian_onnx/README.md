# marian_onnx

Native MarianMT decode with ONNX Runtime KV-cache (`decoder_with_past`).

Generation (greedy / incremental beam) runs entirely in C++. Dart calls
`marian_onnx_translate` once per utterance.

## Layout

| Target | Links ORT / SentencePiece | Purpose |
|--------|---------------------------|---------|
| `marian_onnx_decode` | no | Static lib: `generate()` loop |
| `marian_onnx_decode_test` | no | Fake-session unit tests |
| `marian_onnx` (shared) | yes | Windows DLL / Android `.so` FFI |

## Decode tests (no ORT)

```bat
cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build --target marian_onnx_decode_test
build\marian_onnx_decode_test.exe
```

## Windows DLL

1. Download a prebuilt [ONNX Runtime](https://github.com/microsoft/onnxruntime/releases) Windows x64 zip (e.g. `onnxruntime-win-x64-1.20.1.zip`) and point `ONNXRUNTIME_ROOT` at the extracted folder (`include/` + `lib/onnxruntime.lib`).
2. Build with **MSVC** (MinGW cannot link the official MSVC import lib):

```bat
cmake -S . -B build_dll -G "Visual Studio 17 2022" -A x64 ^
  -DMARIAN_ONNX_BUILD_DLL=ON -DONNXRUNTIME_ROOT=%ONNXRUNTIME_ROOT%
cmake --build build_dll --config Release --target marian_onnx
```

Output: `build_dll/Release/marian_onnx.dll`. A standalone run needs `onnxruntime.dll` beside that DLL. The Flutter Windows runner must not receive it: sherpa-onnx already installs ORT 1.28 as `onnxruntime.dll`, and `marian_onnx.dll` binds to that copy.

## Android `.so` (Flutter Gradle)

`android/app/build.gradle` builds `libmarian_onnx.so` via `externalNativeBuild`.
CMake fetches `onnxruntime-android` 1.20.0 (AAR) and ships it as
`libort_marian.so` (private SONAME). sherpa-onnx keeps its own
`libonnxruntime.so`. Dart loads `libmarian_onnx.so` from the APK.

SentencePiece is fetched by CMake (FetchContent). Load from Dart via
`MarianOnnxFfiBridge.openDefault()`.

## Model folder

Required files:

- `encoder_model.onnx`
- `decoder_model.onnx` (must emit `present.*` KV)
- `decoder_with_past_model.onnx`
- `source.spm`, `target.spm`
- `tokenizer_config.json`, `generation_config.json`, `config.json`

Export with Hugging Face Optimum `ORTModelForSeq2SeqLM`.

For Malinali's FR↔EN and Wolof packs, use the curated recipe:

[`tool/export_marian_onnx/README.md`](../../tool/export_marian_onnx/README.md)
