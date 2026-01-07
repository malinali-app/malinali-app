# Malinali - Local Translation App

An offline-first Flutter app for translation using retrieval-based translation combining Full Text Search (FTS) and Semantic Search on any datasets.

## Context

While advanced translation models give good results (e.g. [nllb](https://huggingface.co/flutter-painter/nllb-fra-fuf-v2)), they are too heavy to run locally and incompatible with mobile OS...

And while there are offline Machine Translations tools like OpenNMT, CTranslate2, or INMT-lite. To yield good results, they need a vast amount of data that is intrinsically not available for low-resource languages.

As a result Malinali takes a diffrent approach and rely on a **retrieval-based translation** rather than generative neural translation. 

1. Semantic Search using embeddings/vector, based on
    - a tiny embedder [all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) that runs using [fonnx](https://github.com/Telosnex/fonnx)
    - a [forked version](https://github.com/malinali-app/ml_algo) of [ml_algo](https://pub.dev/packages/ml_algo) that stores embeddings in SQLite and retrives the nearest using [RandomBinaryProjectionSearcher](https://pub.dev/documentation/ml_algo/latest/ml_algo/RandomBinaryProjectionSearcher-class.html)
2. Full Text Search based on SQLite

Combining the two techniques allows users to compare the two results, often illustrating that the semantic yields better results.
The app also displays the source text linked with the translation found, allowing users to assess if context matches and thus if the translation is relevant.

![screenshot.png](screenshot.png)

This approach is **imperfect but pragmatic**:

- **Works offline**: All data stored locally, no API calls
- **Mobile-friendly**: Flutter app, runs smoothly on low-end devices

**Caveats**:
Translations may be imperfect, users need to review, evaluate, and select the most relevant and options from the suggestions, provided they are in indeed accurate or else discard them and

**When to use Malinali:**

- Low-resource languages with limited training data
- __translations Hands on assessment/selection__
- Offline-first requirements
- Privacy-sensitive applications
- Resource-constrained environments
- Domain-specific translations available for custom use (e.g., medical, legal, technical)

## How to run

1. download 
- https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/blob/main/onnx/model.onnx
- https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/blob/main/tokenizer.json

2. paste them in assets/models/

3. run the app and either import your own data or use default demo

## Demo Dataset

less than a 1 000 lines from :
License-free french/english -> fula dataset from [awesome_fula_nl_resources](https://github.com/flutter-painter/awesome_fula_nl_resources)

Full versions contains 15 000 french/english/fula and yields quick results

## Future Improvements

- Allow users to add additional language support
- Explore a French-Specific Embedding Models
  - `sentence-camembert-base` or `dangvantuan/french-document-embedding`
- Allow users to use a wider range of embedding models 