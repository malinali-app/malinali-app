// ignore_for_file: implementation_imports
import 'dart:ffi';
import 'package:fonnx/onnx/ort.dart';
import 'package:ffi/ffi.dart';

/// Helper class to inspect ONNX model output names
class ModelOutputInspector {
  /// Gets the first output name from the model
  /// This is useful when the fonnx package expects "embeddings" but the model has a different name
  static String? getFirstOutputName(String modelPath) {
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

