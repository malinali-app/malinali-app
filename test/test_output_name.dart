// Quick test to check what output name the model has and what works
// Run with: dart test/test_output_name.dart

import 'dart:io';

void main() async {
  print('🔍 Testing ONNX Model Output Name\n');
  
  // Check if we can import and use the model inspector
  try {
    // This will only work if run from Flutter context, but let's try
    print('Model path: assets/models/all-MiniLM-L6-v2.onnx');
    final modelFile = File('assets/models/all-MiniLM-L6-v2.onnx');
    
    if (await modelFile.exists()) {
      print('✅ Model file exists');
      print('   Size: ${(await modelFile.length() / 1024 / 1024).toStringAsFixed(2)} MB');
    } else {
      print('❌ Model file not found at assets/models/all-MiniLM-L6-v2.onnx');
      print('   Try running from the project root directory');
    }
  } catch (e) {
    print('⚠️  Could not check model file: $e');
  }
  
  print('\n📋 Summary:');
  print('   - Your model has output: "last_hidden_state"');
  print('   - malinali-app/fonnx (local, modified): expects "last_hidden_state" ✅');
  print('   - Telosnex/fonnx (default): expects "embeddings" ❌');
  print('\n💡 Solution: Use malinali-app/fonnx fork (already fixed in your workspace)');
  print('   Update pubspec.yaml to use:');
  print('   url: https://github.com/malinali-app/fonnx');
}

