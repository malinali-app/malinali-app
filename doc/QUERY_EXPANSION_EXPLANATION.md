# Query Expansion Techniques for Religious Text Translation

## Option 1: Word Stemming/Lemmatization

### What is Stemming?

**Stemming** reduces words to their root form by removing suffixes.

**Examples:**
- "worshipping" → "worship"
- "worshipped" → "worship"
- "believers" → "believ"
- "believing" → "believ"
- "praying" → "pray"
- "prayed" → "pray"

### What is Lemmatization?

**Lemmatization** is smarter - it reduces words to their dictionary form (lemma) using linguistic knowledge.

**Examples:**
- "worshipping" → "worship" (verb)
- "worshipped" → "worship" (verb)
- "believers" → "believer" (noun)
- "believing" → "believe" (verb)
- "praying" → "pray" (verb)
- "prayed" → "pray" (verb)

**Key Difference:**
- Stemming: "believers" → "believ" (not a real word)
- Lemmatization: "believers" → "believer" (real word, correct form)

### Why This Matters for Your Dataset

**Problem:**
- User types: "I am worshipping"
- Dataset has: "It is You [Alone] whom we **worship**"
- FTS search for "worshipping" won't find "worship" (exact match fails)

**Solution with Stemming/Lemmatization:**
1. User query: "I am worshipping"
2. Extract keywords: ["worshipping"]
3. Stem/Lemmatize: ["worship"]
4. Search for: "worship" ✅ (finds matches!)

### Implementation Approaches

#### Approach A: Simple Stemming (Porter Stemmer)
```dart
// Example: Simple suffix removal
String stemWord(String word) {
  // Remove common suffixes
  if (word.endsWith('ing')) return word.substring(0, word.length - 3);
  if (word.endsWith('ed')) return word.substring(0, word.length - 2);
  if (word.endsWith('s')) return word.substring(0, word.length - 1);
  if (word.endsWith('er')) return word.substring(0, word.length - 2);
  return word;
}

// Usage:
String query = "I am worshipping";
List<String> keywords = query.split(' ')
    .map((w) => stemWord(w.toLowerCase()))
    .toList();
// Result: ["i", "am", "worship"]
```

#### Approach B: Proper Lemmatization (requires dictionary)
```dart
// Use a lemmatization library or dictionary
Map<String, String> lemmaDict = {
  'worshipping': 'worship',
  'worshipped': 'worship',
  'believers': 'believer',
  'believing': 'believe',
  'praying': 'pray',
  'prayed': 'pray',
  // ... more mappings
};

String lemmatize(String word) {
  return lemmaDict[word.toLowerCase()] ?? word.toLowerCase();
}
```

#### Approach C: SQLite FTS with Porter Stemmer
SQLite FTS5 has built-in tokenization, but you can pre-process:

```dart
// Before FTS query, stem the keywords
String userQuery = "I am worshipping";
List<String> stemmedKeywords = userQuery
    .split(' ')
    .map(stemWord)
    .where((w) => w.length > 2) // filter short words
    .toList();

// Build FTS query: "worship" OR "am" OR "i"
String ftsQuery = stemmedKeywords.join(' OR ');
// SQL: SELECT * FROM translations WHERE english_text MATCH 'worship OR am OR i'
```

### Real Example from Your Dataset

**User Query:** "How do I pray?"

**Without Stemming:**
- FTS searches for: "pray"
- Dataset has: "perform Salat" (no match ❌)

**With Stemming + Synonym Expansion:**
- Stem: "pray" → "pray"
- Expand: "pray" → ["pray", "worship", "Salat", "perform"]
- FTS searches for: "pray OR worship OR Salat OR perform"
- Dataset has: "perform Salat" ✅ (match!)

---

## Option 3: Map Common Terms to Dataset Vocabulary

### The Problem

Users use everyday language, but your dataset uses religious/formal terminology:

**User says:** "pray"
**Dataset has:** "perform Salat"

**User says:** "fast"
**Dataset has:** "observe fasting" or "Ramadan"

**User says:** "charity"
**Dataset has:** "pay Zakat" or "spend in obedience to Allah"

### The Solution: Term Mapping Dictionary

Create a mapping from common terms to dataset vocabulary.

### Implementation

#### Step 1: Build a Term Mapping Dictionary

```dart
class ReligiousTermMapper {
  // Map: common term → [dataset terms to search for]
  static final Map<String, List<String>> termMap = {
    // Prayer-related
    'pray': ['pray', 'worship', 'Salat', 'perform Salat', 'prayer'],
    'praying': ['pray', 'worship', 'Salat', 'performing Salat'],
    'prayer': ['pray', 'worship', 'Salat', 'prayer'],
    
    // Charity-related
    'charity': ['Zakat', 'pay Zakat', 'spend', 'spending', 'charity'],
    'give': ['spend', 'Zakat', 'pay', 'give'],
    'donate': ['spend', 'Zakat', 'pay'],
    
    // Fasting-related
    'fast': ['fasting', 'observe fasting', 'Ramadan', 'fast'],
    'fasting': ['fasting', 'observe fasting', 'Ramadan'],
    
    // Belief-related
    'believe': ['believe', 'belief', 'faith', 'believe in'],
    'believer': ['believer', 'believers', 'those who believe'],
    'faith': ['faith', 'belief', 'believe'],
    
    // God-related
    'god': ['Allah', 'Lord', 'God', 'Allah'],
    'lord': ['Lord', 'Allah', 'God'],
    
    // Afterlife-related
    'heaven': ['Paradise', 'Gardens', 'heaven'],
    'hell': ['Fire', 'Hell', 'punishment'],
    'judgment': ['Day of Retribution', 'Day of Resurrection', 'judgment'],
    
    // General religious
    'worship': ['worship', 'adore', 'worshipping'],
    'sin': ['sin', 'wrongdoing', 'evil'],
    'repent': ['repent', 'repentance', 'repent'],
    'forgive': ['forgive', 'forgiveness', 'mercy'],
  };
  
  /// Expand a user query with dataset vocabulary
  static List<String> expandQuery(String userQuery) {
    final words = userQuery.toLowerCase().split(RegExp(r'\s+'));
    final expandedTerms = <String>{};
    
    // Add original words
    expandedTerms.addAll(words);
    
    // For each word, add mapped terms
    for (final word in words) {
      final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '');
      if (termMap.containsKey(cleanWord)) {
        expandedTerms.addAll(termMap[cleanWord]!);
      }
    }
    
    return expandedTerms.toList();
  }
  
  /// Build FTS query from expanded terms
  static String buildFtsQuery(String userQuery) {
    final expanded = expandQuery(userQuery);
    // Use OR to match any of the expanded terms
    return expanded.join(' OR ');
  }
}
```

#### Step 2: Use in Search

```dart
Future<void> _translate() async {
  final inputText = _inputController.text.trim();
  
  // Expand query with term mapping
  final expandedQuery = ReligiousTermMapper.buildFtsQuery(inputText);
  
  // Use expanded query for FTS
  final keywordResults = await _searcher!.searchByKeyword(
    expandedQuery, // Instead of inputText
    k: 10, // Get more results for ranking
  );
  
  // Then use hybrid search with original embedding
  if (keywordResults.isNotEmpty) {
    final results = await _searcher!.searchHybrid(
      keyword: expandedQuery, // Expanded for FTS
      embedding: queryEmbedding, // Original for semantic
      k: 5,
    );
  }
}
```

### Real Example

**User Input:** "How do I pray?"

**Step 1: Extract keywords**
- Keywords: ["how", "do", "i", "pray"]

**Step 2: Map "pray"**
- "pray" → ["pray", "worship", "Salat", "perform Salat", "prayer"]

**Step 3: Build FTS query**
- FTS Query: `"how" OR "do" OR "i" OR "pray" OR "worship" OR "Salat" OR "perform Salat" OR "prayer"`

**Step 4: Search**
- Finds: "It is You [Alone] whom we **worship**" ✅
- Finds: "perform **Salat**" ✅
- Finds: "**prayer**" ✅

### Advanced: Context-Aware Mapping

You can make it smarter by detecting religious context:

```dart
class ContextAwareTermMapper {
  static bool isReligiousQuery(String query) {
    final religiousKeywords = [
      'pray', 'worship', 'god', 'allah', 'heaven', 'hell',
      'prophet', 'quran', 'islam', 'muslim', 'fast', 'charity'
    ];
    final lowerQuery = query.toLowerCase();
    return religiousKeywords.any((keyword) => lowerQuery.contains(keyword));
  }
  
  static List<String> expandQuery(String userQuery) {
    final expanded = ReligiousTermMapper.expandQuery(userQuery);
    
    // If religious query, add more religious terms
    if (isReligiousQuery(userQuery)) {
      // Add common religious phrases
      expanded.addAll([
        'Allah', 'Lord', 'Prophet', 'Quran', 'Book',
        'Paradise', 'Fire', 'Day of Retribution'
      ]);
    }
    
    return expanded;
  }
}
```

### Building the Dictionary from Your Dataset

You can automatically extract common terms from your dataset:

```dart
// Analyze dataset to find common religious terms
Future<Map<String, List<String>>> buildTermMapFromDataset() async {
  final dataset = await loadDataset();
  final termFrequency = <String, int>{};
  
  // Extract all words from English dataset
  for (final line in dataset.englishLines) {
    final words = line.toLowerCase().split(RegExp(r'\s+'));
    for (final word in words) {
      termFrequency[word] = (termFrequency[word] ?? 0) + 1;
    }
  }
  
  // Find religious terms (appear frequently)
  final religiousTerms = termFrequency.entries
      .where((e) => e.value > 10) // Appears at least 10 times
      .map((e) => e.key)
      .toList();
  
  // Build mapping (simplified - you'd want smarter grouping)
  final termMap = <String, List<String>>{};
  for (final term in religiousTerms) {
    // Group similar terms
    termMap[term] = [term, ...findSimilarTerms(term)];
  }
  
  return termMap;
}
```

### Combining Both Approaches

**Best approach: Use both!**

```dart
String processQuery(String userQuery) {
  // 1. Stem/Lemmatize
  final stemmed = stemWords(userQuery);
  
  // 2. Map to dataset vocabulary
  final mapped = expandWithTermMap(stemmed);
  
  // 3. Build FTS query
  return mapped.join(' OR ');
}
```

This gives you:
- ✅ Handles word variations (worshipping → worship)
- ✅ Maps common terms to religious vocabulary (pray → Salat)
- ✅ Increases match probability significantly

