import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'native_bridge.dart';
import 'translation_config.dart';

typedef _LoadNative = Pointer<Void> Function(Pointer<Utf8> modelDir);
typedef _LoadDart = Pointer<Void> Function(Pointer<Utf8> modelDir);

typedef _TranslateNative = Pointer<Utf8> Function(
  Pointer<Void> handle,
  Pointer<Utf8> text,
  Int32 numBeams,
  Int32 maxNewTokens,
  Double lengthPenalty,
  Int32 noRepeatNgramSize,
);
typedef _TranslateDart = Pointer<Utf8> Function(
  Pointer<Void> handle,
  Pointer<Utf8> text,
  int numBeams,
  int maxNewTokens,
  double lengthPenalty,
  int noRepeatNgramSize,
);

typedef _FreeStringNative = Void Function(Pointer<Utf8> s);
typedef _FreeStringDart = void Function(Pointer<Utf8> s);

typedef _FreeNative = Void Function(Pointer<Void> handle);
typedef _FreeDart = void Function(Pointer<Void> handle);

typedef _LastErrorNative = Pointer<Utf8> Function();
typedef _LastErrorDart = Pointer<Utf8> Function();

/// FFI bridge to `marian_onnx` (Windows DLL / Android `.so`).
class MarianOnnxFfiBridge implements MarianOnnxNativeBridge {
  MarianOnnxFfiBridge._(this._lib)
      : _load = _lib.lookupFunction<_LoadNative, _LoadDart>('marian_onnx_load'),
        _translate =
            _lib.lookupFunction<_TranslateNative, _TranslateDart>(
                'marian_onnx_translate'),
        _freeString =
            _lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
                'marian_onnx_string_free'),
        _free =
            _lib.lookupFunction<_FreeNative, _FreeDart>('marian_onnx_free'),
        _lastError =
            _lib.lookupFunction<_LastErrorNative, _LastErrorDart>(
                'marian_onnx_last_error');

  final DynamicLibrary _lib;
  final _LoadDart _load;
  final _TranslateDart _translate;
  final _FreeStringDart _freeString;
  final _FreeDart _free;
  final _LastErrorDart _lastError;

  /// Open [libraryPath] (`marian_onnx.dll` or `libmarian_onnx.so`).
  static MarianOnnxFfiBridge open(String libraryPath) {
    if (!Platform.isWindows && !Platform.isAndroid) {
      throw UnsupportedError(
        'MarianOnnxFfiBridge is Android/Windows in this slice',
      );
    }
    if (Platform.isWindows) {
      final siblingOrt = File(p.join(File(libraryPath).parent.path, 'onnxruntime.dll'));
      if (siblingOrt.existsSync()) {
        DynamicLibrary.open(siblingOrt.path);
      }
    }
    return MarianOnnxFfiBridge._(DynamicLibrary.open(libraryPath));
  }

  /// Locate the native library, or `libmarian_onnx.so` on Android (APK jniLibs).
  static String? resolveDllPath() {
    if (Platform.isAndroid) return 'libmarian_onnx.so';
    if (!Platform.isWindows) return null;
    const dll = 'marian_onnx.dll';
    final candidates = <String>[
      p.join(File(Platform.resolvedExecutable).parent.path, dll),
      p.join(Directory.current.path, dll),
      p.join(
        Directory.current.path,
        'native',
        'marian_onnx',
        'build_dll',
        'Release',
        dll,
      ),
      p.join(
        Directory.current.path,
        'native',
        'marian_onnx',
        'build_dll',
        'Debug',
        dll,
      ),
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Open the platform default native library.
  static MarianOnnxFfiBridge openDefault() {
    final path = resolveDllPath();
    if (path == null) {
      throw StateError(
        'marian_onnx native library not found (Windows DLL or Android .so)',
      );
    }
    return open(path);
  }

  String _error() {
    final p = _lastError();
    if (p == nullptr) return 'unknown native error';
    return p.toDartString();
  }

  @override
  int load(String modelDir) {
    final dirPtr = modelDir.toNativeUtf8();
    try {
      final handle = _load(dirPtr);
      if (handle == nullptr) {
        throw StateError('marian_onnx_load failed: ${_error()}');
      }
      return handle.address;
    } finally {
      malloc.free(dirPtr);
    }
  }

  @override
  String translate(int handle, String text, OnnxTranslationConfig config) {
    final textPtr = text.toNativeUtf8();
    try {
      final result = _translate(
        Pointer<Void>.fromAddress(handle),
        textPtr,
        config.numBeams,
        config.maxNewTokens,
        config.lengthPenalty,
        config.noRepeatNgramSize,
      );
      if (result == nullptr) {
        throw StateError('marian_onnx_translate failed: ${_error()}');
      }
      try {
        return result.toDartString();
      } finally {
        _freeString(result);
      }
    } finally {
      malloc.free(textPtr);
    }
  }

  @override
  void free(int handle) {
    _free(Pointer<Void>.fromAddress(handle));
  }
}
