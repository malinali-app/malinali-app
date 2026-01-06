import 'package:stemmer/stemmer.dart';

/// Simple stemmer for FTS queries
/// Uses Porter stemmer for English (default), simple rules for French
class QueryStemmer {
  static final _stemmer = SnowballStemmer();

  /// Stem a word
  /// Uses Porter stemmer (English-focused, but works reasonably for French too)
  static String stemWord(String word) {
    if (word.length < 3) return word.toLowerCase();
    return _stemmer.stem(word);
  }

  /// Stem all words in a query for FTS
  /// Returns stemmed query string suitable for FTS search
  static String stemQuery(String query) {
    // Split into words, keeping punctuation for FTS
    final words = query.split(RegExp(r'\s+'));
    final stemmedWords = words.map((word) {
      // Remove punctuation for stemming, but keep original if it's punctuation-only
      final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '');
      if (cleanWord.isEmpty) return word;
      
      final stemmed = stemWord(cleanWord);
      // Preserve original capitalization/punctuation structure
      return word.replaceAll(cleanWord, stemmed);
    }).toList();
    
    return stemmedWords.join(' ');
  }
}

