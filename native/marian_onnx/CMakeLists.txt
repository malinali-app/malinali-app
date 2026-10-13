cmake_minimum_required(VERSION 3.16)
project(marian_onnx LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(marian_onnx_decode STATIC
  src/decode.cc
)
target_include_directories(marian_onnx_decode PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Decode unit tests: no ORT, no SentencePiece (host builds only).
if(NOT ANDROID)
  add_executable(marian_onnx_decode_test
    test/decode_test.cc
  )
  target_link_libraries(marian_onnx_decode_test PRIVATE marian_onnx_decode)
  enable_testing()
  add_test(NAME decode_test COMMAND marian_onnx_decode_test)
endif()

# Optional ORT + SentencePiece shared lib (Windows DLL / Android .so).
option(MARIAN_ONNX_BUILD_DLL "Build Windows FFI DLL with ORT" OFF)
option(MARIAN_ONNX_BUILD_SHARED "Build FFI shared library with ORT" OFF)
if(MARIAN_ONNX_BUILD_DLL)
  set(MARIAN_ONNX_BUILD_SHARED ON)
endif()
if(ANDROID)
  set(MARIAN_ONNX_BUILD_SHARED ON)
endif()
if(MARIAN_ONNX_BUILD_SHARED)
  if(NOT ONNXRUNTIME_ROOT AND DEFINED ENV{ONNXRUNTIME_ROOT})
    set(ONNXRUNTIME_ROOT $ENV{ONNXRUNTIME_ROOT})
  endif()
  if(ANDROID AND NOT ONNXRUNTIME_ROOT)
    # CMake 3.22 (Android SDK) cannot FetchContent this URL: it treats
    # extra keywords as a second URL entry. Download the AAR (a zip) directly.
    set(_ort_ver "1.20.0")
    set(_ort_cache "${CMAKE_CURRENT_SOURCE_DIR}/../../build/onnxruntime-android-${_ort_ver}")
    set(_ort_aar "${_ort_cache}.aar")
    if(NOT EXISTS "${_ort_cache}/jni/${ANDROID_ABI}/libonnxruntime.so")
      file(MAKE_DIRECTORY "${_ort_cache}")
      set(_ort_url "https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/${_ort_ver}/onnxruntime-android-${_ort_ver}.aar")
      message(STATUS "Downloading ONNX Runtime Android ${_ort_ver}")
      file(DOWNLOAD "${_ort_url}" "${_ort_aar}" STATUS _ort_dl SHOW_PROGRESS)
      list(GET _ort_dl 0 _ort_code)
      if(NOT _ort_code EQUAL 0)
        list(GET _ort_dl 1 _ort_msg)
        message(FATAL_ERROR "ONNX Runtime download failed: ${_ort_msg}")
      endif()
      file(ARCHIVE_EXTRACT INPUT "${_ort_aar}" DESTINATION "${_ort_cache}")
    endif()
    set(ONNXRUNTIME_ROOT "${_ort_cache}")
  endif()
  if(NOT ONNXRUNTIME_ROOT)
    message(FATAL_ERROR "Set ONNXRUNTIME_ROOT to a prebuilt ONNX Runtime SDK")
  endif()

  include(FetchContent)
  set(SPM_ENABLE_SHARED OFF CACHE BOOL "" FORCE)
  set(SPM_ENABLE_TCMALLOC OFF CACHE BOOL "" FORCE)
  set(SPM_BUILD_TEST OFF CACHE BOOL "" FORCE)
  set(SPM_USE_BUILTIN_PROTOBUF ON CACHE BOOL "" FORCE)
  FetchContent_Declare(
    sentencepiece
    GIT_REPOSITORY https://github.com/google/sentencepiece.git
    GIT_TAG v0.2.0
  )
  FetchContent_MakeAvailable(sentencepiece)
  if(ANDROID AND TARGET sentencepiece-static)
    # protobuf-lite logs via __android_log_write. Propagate liblog so the
    # static archive links inside marian_onnx and any SentencePiece tools.
    target_link_libraries(sentencepiece-static PUBLIC log)
  endif()

  add_library(marian_onnx SHARED
    src/ffi_api.cc
    src/ort_session.cc
    src/tokenizer.cc
  )
  set(_ORT_INCLUDE "${ONNXRUNTIME_ROOT}/include")
  if(NOT EXISTS "${_ORT_INCLUDE}/onnxruntime_cxx_api.h")
    if(EXISTS "${ONNXRUNTIME_ROOT}/headers/onnxruntime/onnxruntime_cxx_api.h")
      set(_ORT_INCLUDE "${ONNXRUNTIME_ROOT}/headers/onnxruntime")
    elseif(EXISTS "${ONNXRUNTIME_ROOT}/headers/onnxruntime_cxx_api.h")
      set(_ORT_INCLUDE "${ONNXRUNTIME_ROOT}/headers")
    elseif(EXISTS "${ONNXRUNTIME_ROOT}/prefab/onnxruntime/include/onnxruntime_cxx_api.h")
      set(_ORT_INCLUDE "${ONNXRUNTIME_ROOT}/prefab/onnxruntime/include")
    endif()
  endif()
  target_include_directories(marian_onnx PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${_ORT_INCLUDE}
  )
  target_compile_definitions(marian_onnx PRIVATE MARIAN_ONNX_EXPORTS)
  target_link_libraries(marian_onnx PRIVATE marian_onnx_decode)

  if(NOT MSVC)
    target_compile_options(marian_onnx PRIVATE -fvisibility=hidden)
    if(ANDROID)
      target_link_options(marian_onnx PRIVATE "-Wl,--version-script,${CMAKE_CURRENT_SOURCE_DIR}/marian_onnx.lds")
    endif()
  endif()

  # SentencePiece static target name varies slightly by version.
  if(TARGET sentencepiece-static)
    target_link_libraries(marian_onnx PRIVATE sentencepiece-static)
  elseif(TARGET sentencepiece)
    target_link_libraries(marian_onnx PRIVATE sentencepiece)
  else()
    message(FATAL_ERROR "SentencePiece target not found after FetchContent")
  endif()

  # Headers live under the FetchContent source tree.
  if(DEFINED sentencepiece_SOURCE_DIR)
    target_include_directories(marian_onnx PRIVATE
      ${sentencepiece_SOURCE_DIR}/src
      ${sentencepiece_BINARY_DIR}/src
    )
  endif()

  set(_ORT_SO "")
  if(ANDROID)
    set(_ort_upstream "${ONNXRUNTIME_ROOT}/jni/${ANDROID_ABI}/libonnxruntime.so")
    if(NOT EXISTS "${_ort_upstream}")
      set(_ort_upstream "${ONNXRUNTIME_ROOT}/prefab/onnxruntime/libs/android.${ANDROID_ABI}/libonnxruntime.so")
    endif()
    if(EXISTS "${_ort_upstream}")
      # Private SONAME so this copy does not replace sherpa-onnx's runtime.
      set(_ORT_SO "${CMAKE_CURRENT_BINARY_DIR}/libort_marian.so")
      execute_process(
        COMMAND python "${CMAKE_CURRENT_SOURCE_DIR}/rename_ort_soname.py"
          "${_ort_upstream}" "${_ORT_SO}"
        COMMAND_ERROR_IS_FATAL ANY
      )
    endif()
  endif()
  if(_ORT_SO)
    add_library(onnxruntime SHARED IMPORTED)
    set_target_properties(onnxruntime PROPERTIES IMPORTED_LOCATION "${_ORT_SO}")
    target_link_libraries(marian_onnx PRIVATE onnxruntime)
    if(CMAKE_LIBRARY_OUTPUT_DIRECTORY)
      # Drop a previous build that overwrote sherpa's libonnxruntime.so.
      file(REMOVE "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/libonnxruntime.so")
      add_custom_command(TARGET marian_onnx POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
          "${_ORT_SO}"
          "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/libort_marian.so")
    endif()
  elseif(EXISTS "${ONNXRUNTIME_ROOT}/lib/onnxruntime.lib")
    target_link_libraries(marian_onnx PRIVATE
      "${ONNXRUNTIME_ROOT}/lib/onnxruntime.lib")
  elseif(EXISTS "${ONNXRUNTIME_ROOT}/lib/libonnxruntime.so")
    target_link_libraries(marian_onnx PRIVATE
      "${ONNXRUNTIME_ROOT}/lib/libonnxruntime.so")
  elseif(EXISTS "${ONNXRUNTIME_ROOT}/lib/libonnxruntime.dylib")
    target_link_libraries(marian_onnx PRIVATE
      "${ONNXRUNTIME_ROOT}/lib/libonnxruntime.dylib")
  else()
    file(GLOB _ort_dll "${ONNXRUNTIME_ROOT}/lib/onnxruntime.dll"
                       "${ONNXRUNTIME_ROOT}/bin/onnxruntime.dll")
    if(_ort_dll)
      target_link_libraries(marian_onnx PRIVATE ${_ort_dll})
    else()
      message(FATAL_ERROR
        "No onnxruntime library under ${ONNXRUNTIME_ROOT}")
    endif()
  endif()

  if(MSVC)
    target_compile_options(marian_onnx PRIVATE /EHsc)
  endif()
  if(ANDROID)
    target_link_libraries(marian_onnx PRIVATE log)
    target_link_options(marian_onnx PRIVATE "-Wl,-z,max-page-size=16384")
  endif()
endif()
