import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Dart Marian tests fake the native bridge. This one guards the Windows
/// packaging bug: Marian's ORT 1.20 DLL must not replace sherpa's
/// `onnxruntime.dll` (API 28). Android keeps its private `libort_marian.so`.
void main() {
  final windowsCmake = File('windows/CMakeLists.txt').readAsStringSync();
  final androidCmake = File('native/marian_onnx/CMakeLists.txt').readAsStringSync();

  test('Windows bundle installs marian_onnx.dll and not onnxruntime.dll', () {
    final code = windowsCmake.split('\n').map((line) {
      final hash = line.indexOf('#');
      return hash < 0 ? line : line.substring(0, hash);
    }).join('\n');
    expect(code, contains('marian_onnx.dll'));
    expect(code, isNot(contains('onnxruntime')));
  });

  test('Android Marian runtime keeps the private SONAME', () {
    expect(androidCmake, contains('libort_marian.so'));
    expect(androidCmake, contains('rename_ort_soname.py'));
  });
}
