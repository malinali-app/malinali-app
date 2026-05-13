import 'package:libsql_dart/libsql_dart.dart';
import 'package:malinali/services/storage_service.dart';
import 'dart:async';

class SearchResult {
  final String source;
  final String target;
  final double? rank;
  final List<String> matchedTerms;

  SearchResult({
    required this.source,
    required this.target,
    this.rank,
    this.matchedTerms = const [],
  });
}

class SearchService {
  LibsqlClient? _client;
  bool _isInitialized = false;

  static const _stopWords = {
    'le',
    'la',
    'les',
    'de',
    'des',
    'un',
    'une',
    'et',
    'en',
    'ce',
    'ces',
    'du',
    'au',
    'aux',
    'à',
    'a',
    'd',
    'l',
    'que',
    'qui',
    'se',
    'sa',
    'son',
    'ses',
    'leur',
    'leurs',
    'mon',
    'ma',
    'mes',
    'ton',
    'ta',
    'tes',
    'sur',
    'dans',
    'pour',
    'par',
    'avec',
    'sans',
    'ne',
    'pas',
    'est',
    'sont',
    'été',
    'etre',
    'être',
    'il',
    'elle',
    'ils',
    'elles',
    'on',
    'nous',
    'vous',
    'je',
    'tu',
  };

  static const int _maxResults = 25;

  bool get isInitialized => _isInitialized;

  /// For testing purposes
  void setClient(LibsqlClient client) {
    _client = client;
    _isInitialized = true;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    final dbPath = await StorageService.getSyncDatabasePath();
    
    _client = LibsqlClient(dbPath);
    await _client!.connect();

    // Ensure tables exist
    await _client!.execute('''
      CREATE TABLE IF NOT EXISTS dictionary (
          source_word TEXT PRIMARY KEY,
          translated_word TEXT,
          category TEXT,
          source TEXT
      );
    ''');

    // FTS5 table for documents
    await _client!.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS documents USING fts5(
          content, 
          tokenize = 'unicode61'
      );
    ''');

    _isInitialized = true;
  }

  String _stripContraction(String word) {
    if (word.length > 2 && word[1] == "'") {
      return word.substring(2);
    }
    return word;
  }

  bool _isMeaningfulWord(String word) {
    final processedWord = _stripContraction(word);
    return processedWord.length > 1 && !_stopWords.contains(processedWord);
  }

  Future<Map<String, List<String>>> getExpansions(List<String> words) async {
    if (!_isInitialized || _client == null) return {};

    Map<String, List<String>> expansions = {};
    
    for (var word in words) {
      final processedWord = _stripContraction(word);
      if (!_isMeaningfulWord(word)) continue;

      final results = await _client!.query(
        "SELECT translated_word FROM dictionary WHERE source_word LIKE ?",
        positional: ['$processedWord%'],
      );

      if (results.isNotEmpty) {
        expansions[processedWord] = results
            .map((r) => r['translated_word'].toString())
            .toSet()
            .toList();
      }
    }
    return expansions;
  }

  String _buildFtsQuery(List<String> words, Map<String, List<String>> expansions) {
    final expandedTerms = <String>[];

    for (final word in words) {
      final processedWord = _stripContraction(word);
      if (!_isMeaningfulWord(word)) continue;

      if (expansions.containsKey(processedWord)) {
        final translations = expansions[processedWord]!;
        final group = ['"$processedWord"', ...translations.map((t) => '"$t"')];
        expandedTerms.add('(${group.join(' OR ')})');
      } else {
        expandedTerms.add('"$processedWord"');
      }
    }

    if (expandedTerms.isEmpty) {
      final meaningfulWords = words
          .map(_stripContraction)
          .where((word) => word.length > 1 && !_stopWords.contains(word))
          .toList();
      if (meaningfulWords.isEmpty) {
        return '"${words.join(' ')}"';
      }
      return meaningfulWords.map((word) => '"$word"').join(' AND ');
    }

    return expandedTerms.join(' AND ');
  }

  Future<List<SearchResult>> search(String userQuery) async {
    if (!_isInitialized || _client == null) return [];

    List<String> words = userQuery.toLowerCase()
        .split(RegExp(r"[^a-zà-ÿ0-9']+"))
        .where((w) => w.isNotEmpty)
        .toList();
    
    final expansions = await getExpansions(words);
    final ftsQuery = _buildFtsQuery(words, expansions);
    final allFulaTerms = expansions.values.expand((terms) => terms).toSet().toList();

    final results = await _client!.query(
      "SELECT content, rank FROM documents WHERE documents MATCH ? ORDER BY rank LIMIT ?",
      positional: [ftsQuery, _maxResults],
    );

    return results.map((row) {
      final content = row['content'].toString();
      final parts = content.split(' → ');
      final source = parts[0];
      final target = parts.length > 1 ? parts[1] : '';
      
      return SearchResult(
        source: source,
        target: target,
        rank: double.tryParse(row['rank'].toString()),
        matchedTerms: allFulaTerms,
      );
    }).toList();
  }

  void dispose() {
    _client?.dispose();
    _client = null;
    _isInitialized = false;
  }
}
