// ignore_for_file: implementation_imports
import 'dart:ffi';
import 'dart:io';
import 'package:fonnx/onnx/ort.dart';
import 'package:ffi/ffi.dart';

/// Helper class to inspect ONNX model output names
class ModelOutputInspector {
  /// Checks if FFI-based inspection is available on this platform
  /// Android uses platform-specific implementations, not FFI
  static bool get _isFfiAvailable {
    // FFI inspection doesn't work on Android - it uses platform-specific implementations
    return !Platform.isAndroid;
  }

  /// Gets the first output name from the model
  /// This is useful when the fonnx package expects "embeddings" but the model has a different name
  static String? getFirstOutputName(String modelPath) {
    if (!_isFfiAvailable) {
      print('⚠️  Model output inspection not available on Android (uses platform-specific implementation)');
      return null;
    }
    
    try {
      final sessionObjects = createOrtSession(modelPath);
      final outputCount = sessionObjects.api.sessionGetOutputCount(
        sessionObjects.sessionPtr.value,
      );
      
      if (outputCount.value == 0) {
        return null;
      }
      
      // Get the first output name (index 0)
      final outputNamePtr = calloc<Pointer<Char>>();
      sessionObjects.api.sessionGetOutputName(
        sessionObjects.sessionPtr.value,
        0,
        outputNamePtr,
      );
      
      final outputName = outputNamePtr.value.toDartString();
      calloc.free(outputNamePtr);
      
      return outputName;
    } catch (e) {
      print('Error inspecting model output name: $e');
      return null;
    }
  }
  
  /// Gets all output names from the model
  static List<String> getAllOutputNames(String modelPath) {
    if (!_isFfiAvailable) {
      print('⚠️  Model output inspection not available on Android (uses platform-specific implementation)');
      return [];
    }
    
    try {
      final sessionObjects = createOrtSession(modelPath);
      final outputCount = sessionObjects.api.sessionGetOutputCount(
        sessionObjects.sessionPtr.value,
      );
      
      final outputNames = <String>[];
      for (var i = 0; i < outputCount.value; i++) {
        final outputNamePtr = calloc<Pointer<Char>>();
        sessionObjects.api.sessionGetOutputName(
          sessionObjects.sessionPtr.value,
          i,
          outputNamePtr,
        );
        outputNames.add(outputNamePtr.value.toDartString());
        calloc.free(outputNamePtr);
      }
      
      calloc.free(outputCount);
      return outputNames;
    } catch (e) {
      print('Error inspecting model output names: $e');
      return [];
    }
  }
}

