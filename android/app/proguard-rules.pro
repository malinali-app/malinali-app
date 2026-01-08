# Keep ONNX Runtime classes that are accessed via JNI
# The native library calls these classes, so they must not be obfuscated or removed
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }

# Keep TensorInfo and all its constructors (critical for JNI)
-keep class ai.onnxruntime.TensorInfo { *; }
-keepclassmembers class ai.onnxruntime.TensorInfo {
    <init>(...);
}

# Keep all ONNX Runtime classes used by native code
-keep class ai.onnxruntime.OrtSession { *; }
-keep class ai.onnxruntime.OrtSession$Result { *; }
-keep class ai.onnxruntime.OnnxTensor { *; }
-keep class ai.onnxruntime.OnnxValue { *; }
-keep class ai.onnxruntime.OrtEnvironment { *; }
-keep class ai.onnxruntime.OrtSessionObjects { *; }

# Keep Kotlin coroutines (used by fonnx plugin)
-keep class kotlin.coroutines.** { *; }
-keepclassmembers class kotlin.coroutines.** { *; }

# Keep fonnx plugin classes
-keep class com.telosnex.fonnx.** { *; }
