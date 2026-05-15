import 'package:malinali/services/storage_service.dart';
import 'package:malinali/services/sync_database_access.dart';
import 'package:malinali/services/turso_sync_service.dart';
import 'package:sqlite3/sqlite3.dart';

class DataSourceAttribution {
  final String name;
  final String author;
  final String year;
  final String organization;
  final String url;

  const DataSourceAttribution({
    required this.name,
    required this.author,
    required this.year,
    required this.organization,
    required this.url,
  });

  bool get hasDetails =>
      author.isNotEmpty ||
      year.isNotEmpty ||
      organization.isNotEmpty ||
      url.isNotEmpty;
}

class SearchResult {
  final String source;
  final String target;
  final double? rank;
  final List<String> matchedTerms;
  final bool isPhrase;
  final DataSourceAttribution? dataSource;

  SearchResult({
    required this.source,
    required this.target,
    this.rank,
    this.matchedTerms = const [],
    this.isPhrase = false,
    this.dataSource,
  });
}

class LexicalTokenMatch {
  final String sourceWord;
  final String translatedWord;
  final String category;

  const LexicalTokenMatch({
    required this.sourceWord,
    required this.translatedWord,
    required this.category,
  });
}

class SearchService {
  Database? _db;
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
  void setDatabase(Database database) {
    _db = database;
    _isInitialized = true;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    final dbPath = await StorageService.getAppDatabasePath();
    await SyncDatabaseAccess.ensureParentDirectory(dbPath);
    final db = SyncDatabaseAccess.tryOpenReadOnly(dbPath);
    if (db == null) {
      throw const TursoConfigurationException(
        'Base de données locale introuvable. Synchronisez Turso ou importez des données.',
      );
    }
    _db = db;
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

  List<String> _tokenize(String userQuery) {
    return userQuery
        .toLowerCase()
        .split(RegExp(r"[^a-zà-ÿ0-9']+"))
        .where((word) => word.isNotEmpty)
        .toList();
  }

  Future<List<LexicalTokenMatch>> lookupLexicalTokens(String userQuery) async {
    if (!_isInitialized || _db == null) return [];

    final matches = <LexicalTokenMatch>[];

    for (final word in _tokenize(userQuery)) {
      final processedWord = _stripContraction(word);
      if (!_isMeaningfulWord(word)) continue;

      final match = _lookupLexicalToken(processedWord);
      if (match != null) {
        matches.add(match);
      }
    }

    return matches;
  }

  LexicalTokenMatch? _lookupLexicalToken(String processedWord) {
    final dictionary = SyncDatabaseAccess.dictionaryTable(_db!);
    if (dictionary == null || dictionary.categoryColumn == null) {
      return null;
    }

    final categoryColumn = dictionary.categoryColumn!;
    final exactRows = _db!.select(
      'SELECT ${dictionary.sourceColumn} AS source_word, '
      '${dictionary.targetColumn} AS translated_word, '
      '$categoryColumn AS category '
      'FROM ${dictionary.tableName} '
      'WHERE lower(${dictionary.sourceColumn}) = lower(?) '
      "AND $categoryColumn IS NOT NULL AND TRIM($categoryColumn) != ''",
      [processedWord],
    );

    if (exactRows.isNotEmpty) {
      final row = exactRows.first;
      return LexicalTokenMatch(
        sourceWord: processedWord,
        translatedWord: row['translated_word'].toString(),
        category: row['category'].toString(),
      );
    }

    final prefixRows = _db!.select(
      'SELECT ${dictionary.sourceColumn} AS source_word, '
      '${dictionary.targetColumn} AS translated_word, '
      '$categoryColumn AS category '
      'FROM ${dictionary.tableName} '
      'WHERE lower(${dictionary.sourceColumn}) LIKE lower(?) '
      "AND $categoryColumn IS NOT NULL AND TRIM($categoryColumn) != '' "
      'ORDER BY LENGTH(${dictionary.sourceColumn}) ASC LIMIT 1',
      ['$processedWord%'],
    );

    if (prefixRows.isEmpty) {
      return null;
    }

    final row = prefixRows.first;
    return LexicalTokenMatch(
      sourceWord: processedWord,
      translatedWord: row['translated_word'].toString(),
      category: row['category'].toString(),
    );
  }

  Future<Map<String, List<String>>> getExpansions(List<String> words) async {
    if (!_isInitialized || _db == null) return {};

    final expansions = <String, List<String>>{};

    for (final word in words) {
      final processedWord = _stripContraction(word);
      if (!_isMeaningfulWord(word)) continue;

      final translations = <String>{};
      for (final table in SyncDatabaseAccess.expansionTables(_db!)) {
        final results = _db!.select(
          'SELECT ${table.targetColumn} AS translated_word '
          'FROM ${table.tableName} '
          'WHERE ${table.sourceColumn} LIKE ?',
          ['$processedWord%'],
        );
        translations.addAll(
          results.map((row) => row['translated_word'].toString()),
        );
      }

      if (translations.isNotEmpty) {
        expansions[processedWord] = translations.toList();
      }
    }

    return expansions;
  }

  String _buildFtsQuery(
    List<String> words,
    Map<String, List<String>> expansions,
  ) {
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
    if (!_isInitialized || _db == null) return [];

    final words = _tokenize(userQuery);

    final expansions = await getExpansions(words);
    final ftsQuery = _buildFtsQuery(words, expansions);
    final allFulaTerms = expansions.values
        .expand((terms) => terms)
        .toSet()
        .toList();

    final results = _db!.select(
      'SELECT content, rank FROM documents WHERE documents MATCH ? ORDER BY rank LIMIT ?',
      [ftsQuery, _maxResults],
    );

    return results.map((row) {
      final content = row['content'].toString();
      final parts = content.split(' → ');
      final source = parts[0];
      final target = parts.length > 1 ? parts[1] : '';

      return _enrichPhraseResult(
        source: source,
        target: target,
        rank: double.tryParse(row['rank'].toString()),
        matchedTerms: allFulaTerms,
      );
    }).toList();
  }

  SearchResult _enrichPhraseResult({
    required String source,
    required String target,
    double? rank,
    List<String> matchedTerms = const [],
  }) {
    final rows = _db!.select(
      '''
      SELECT d.name, d.author, d.year, d.organization, d.url
      FROM phrases p
      LEFT JOIN data_sources d ON d.name = p.source
      WHERE p.source_word = ? AND p.translated_word = ?
      LIMIT 1
      ''',
      [source, target],
    );

    if (rows.isEmpty) {
      return SearchResult(
        source: source,
        target: target,
        rank: rank,
        matchedTerms: matchedTerms,
      );
    }

    final row = rows.first;
    final name = row['name']?.toString() ?? '';
    DataSourceAttribution? dataSource;
    if (name.isNotEmpty) {
      dataSource = DataSourceAttribution(
        name: name,
        author: row['author']?.toString() ?? '',
        year: row['year']?.toString() ?? '',
        organization: row['organization']?.toString() ?? '',
        url: row['url']?.toString() ?? '',
      );
    }

    return SearchResult(
      source: source,
      target: target,
      rank: rank,
      matchedTerms: matchedTerms,
      isPhrase: true,
      dataSource: dataSource,
    );
  }

  void dispose() {
    _db?.dispose();
    _db = null;
    _isInitialized = false;
  }
}
