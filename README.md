# Malinali - Offline Translation App

An offline-first Flutter app for translation using retrieval-based translation combining Full Text Search (FTS) and Semantic Search on any datasets.

## French Context

Malinali est une application de traduction flutter qui fonctionne hors-ligne sur tous les OS, mobiles inclus.
Elle combine recherche sémantique (vectorielle) & recherche par mots clés (full text search)
La démo inclus x800 expressions pour tester la traduction du français => pulaar

Si la qualité des résultats dépend du jeu de données, le système est bien moins efficace que les outils en ligne de MachineTranslation / LLM. Mais c'est une appli libre et gratuite qui permet même d'importer son propre jeu de donnée (dataset).

Un outil pour découvrir/explorer le pulaar voire même d'autres langues dites "low-resources" pour lesquelles il y a peu d'offres.

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

**When to use Malinali:**

- Low-resource languages with limited training data
- Offline-first requirements
- Privacy-sensitive applications
- Resource-constrained environments
- Users ready to review, evaluate suggestions, provided they are accurate
- Domain-specific translations available for custom use (e.g., medical, legal, technical)

## Demo Dataset

License-free x800 lines french -> fula dataset from [awesome_fula_nl_resources](https://github.com/flutter-painter/awesome_fula_nl_resources)
Full versions contains x15 000 lines and still yields quick results :
  - [french](https://github.com/flutter-painter/awesome_fula_nl_resources/blob/main/src_fra_license_free.txt)
  - [fula](https://github.com/flutter-painter/awesome_fula_nl_resources/blob/main/tgt_ful_license_free.txt)
  - [english](https://github.com/flutter-painter/awesome_fula_nl_resources/blob/main/src_eng_license_free.txt) as an alternative source (might need rework on the embedding part set-up for English)

## Future Improvements

- Allow users to add additional language support
- Explore a French-Specific Embedding Models
  - `sentence-camembert-base` or `dangvantuan/french-document-embedding`
- Allow users to use a wider range of embedding models 