# Fixing "Invalid Output Name:embeddings" Error

## Problem

The error `Exception: Invalid Output Name:embeddings` occurs because:

1. **The fonnx package hardcodes the output name as "embeddings"** (see line 185 in `ort_minilm_isolate.dart`)
2. **Your ONNX model has a different output name** (likely `last_hidden_state` or similar)

When the fonnx package tries to access an output named "embeddings" that doesn't exist in your model, ONNX Runtime throws this error.

## Diagnosis

The updated `EmbeddingService` will now:
- Inspect your model's output names during initialization
- Print a warning if "embeddings" is not found
- Provide a clearer error message with the actual output names if inference fails

## Solutions

### Solution 1: Re-export the Model with Correct Output Name (Recommended)

If you have access to the original model (PyTorch/HuggingFace), re-export it with the output name "embeddings":

```python
from transformers import AutoModel
import torch

# Load the model
model = AutoModel.from_pretrained('sentence-transformers/all-MiniLM-L6-v2')

# Export to ONNX with explicit output name
dummy_input = torch.randint(0, 1000, (1, 128))  # Example input shape
torch.onnx.export(
    model,
    dummy_input,
    "all-MiniLM-L6-v2.onnx",
    input_names=['input_ids', 'token_type_ids', 'attention_mask'],
    output_names=['embeddings'],  # <-- This is the key!
    dynamic_axes={
        'input_ids': {0: 'batch_size', 1: 'sequence_length'},
        'token_type_ids': {0: 'batch_size', 1: 'sequence_length'},
        'attention_mask': {0: 'batch_size', 1: 'sequence_length'},
        'embeddings': {0: 'batch_size', 1: 'sequence_length'}
    }
)
```

### Solution 2: Fork and Modify the fonnx Package

1. Fork the fonnx package: https://github.com/Telosnex/fonnx
2. Modify `lib/ort_minilm_isolate.dart` line 185:
   ```dart
   // Change from:
   final embeddingsName = 'embeddings'.toNativeUtf8();
   
   // To (use your model's actual output name):
   final embeddingsName = 'last_hidden_state'.toNativeUtf8();  // or whatever your model uses
   ```
3. Update your `pubspec.yaml` to use your fork:
   ```yaml
   fonnx:
     git:
       url: https://github.com/YOUR_USERNAME/fonnx
       ref: your-branch-name
   ```

### Solution 3: Use a Different Model

Use a model that already has "embeddings" as the output name, or find a pre-exported version that matches the fonnx package's expectations.

### Solution 4: Dynamic Output Name Detection (Advanced)

For a more robust solution, you could modify the fonnx package to:
1. Inspect the model's output names when creating the session
2. Use the first output name dynamically instead of hardcoding "embeddings"

This would require modifying the `_getMiniLmEmbeddingFfi` function in the fonnx package.

## Checking Your Model's Output Names

You can check your model's output names using:

```python
import onnx

model = onnx.load('your_model.onnx')
for output in model.graph.output:
    print(f"Output name: {output.name}")
```

Or use the `ModelOutputInspector` class in the codebase:

```dart
final outputNames = ModelOutputInspector.getAllOutputNames(modelPath);
print('Output names: $outputNames');
```

## Why This Happens in Production

If this error occurs in production but not in development (or vice versa), it could be because:
- Different model files are being used
- The model was exported differently in different environments
- Different versions of the model are deployed

Make sure you're using the same model file across all environments.

## Current Workaround

The updated code will:
1. Detect the issue during initialization and warn you
2. Provide a clearer error message with the actual output names
3. Guide you to the solution

This won't fix the underlying issue, but it will make it much easier to diagnose and fix.

