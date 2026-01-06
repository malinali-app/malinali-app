import 'package:stemmer/stemmer.dart';

/// Supported query languages for stemming.
///
/// Right now we only distinguish between English and French, since those
/// are the languages used as sources in the app.
enum QueryLanguage {
  english,
  french,
}

/// Stemmer for FTS queries.
///
/// - Uses Snowball/Porter stemming for **English**
/// - Uses **very conservative normalization** for **French** to avoid
///   breaking words like "notre" → "notr".
class QueryStemmer {
  // Default constructor of SnowballStemmer() uses an English stemmer.
  // We deliberately only apply this to English queries.
  static final _englishStemmer = SnowballStemmer();

  /// Stem a single word according to the query language.
  static String stemWord(String word, QueryLanguage language) {
    final lower = word.toLowerCase();
    if (lower.length < 3) return lower;

    switch (language) {
      case QueryLanguage.english:
        // Full Porter/Snowball stemming is appropriate for English.
        return _englishStemmer.stem(lower);
      case QueryLanguage.french:
        // For French we currently avoid aggressive stemming because
        // English-focused rules mangle French function words and pronouns
        // (e.g. "notre" → "notr").
        //
        // We still normalize case and leave the token as-is so that FTS
        // can match the surface form stored in the corpus.
        return lower;
    }
  }

  /// Stem all words in a query for FTS.
  ///
  /// Returns a query string suitable for FTS search. Punctuation is
  /// preserved in-place, only alphanumeric spans are stemmed/normalized.
  static String stemQuery(String query, QueryLanguage language) {
    // Split into words, keeping whitespace so we can re-join cleanly.
    final words = query.split(RegExp(r'\s+'));
    final stemmedWords = words.map((word) {
      // Remove punctuation for stemming, but keep original if it's punctuation-only
      final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '');
      if (cleanWord.isEmpty) return word;

      final stemmed = stemWord(cleanWord, language);
      // Preserve original capitalization/punctuation structure by replacing
      // only the alphanumeric span inside the token.
      return word.replaceAll(cleanWord, stemmed);
    }).toList();

    return stemmedWords.join(' ');
  }
}

