# What is "Searcher ID"?

## Simple Explanation

**Searcher ID** is just a **name** to identify a searcher in the database.

Think of it like a label on a box:
- Database = warehouse
- Searcher ID = label on the box
- Box = your translation data

## Example

```dart
// Create searcher with ID 'fula'
final searcher = await HybridFTSSearcher.createFromTranslations(
  store,
  translations,
  searcherId: 'fula', // ← This is just a name
);

// Later, load it by name
final loaded = await HybridFTSSearcher.loadFromStore(store, 'fula');
```

## Why Use It?

You can have **multiple searchers** in the same database:

```dart
// Searcher 1: English/French → Fula
searcherId: 'fula'

// Searcher 2: Spanish → Fula (future)
searcherId: 'fula-spanish'

// Searcher 3: Arabic → Fula (future)
searcherId: 'fula-arabic'
```

All stored in the same database file, but with different IDs.

## For Your Use Case

- **Current**: `'fula'` - handles English→Fula and French→Fula
- **Future**: `'fula-spanish'` - add Spanish→Fula when you get the dataset

Simple as that! It's just a name to find your searcher later.

