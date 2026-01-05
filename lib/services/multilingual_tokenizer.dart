import 'dart:convert';
import 'dart:io';
import 'package:fonnx/tokenizers/wordpiece_tokenizer.dart';

/// Vocabulary maps container
class VocabMaps {
  final Map<String, int> encoder;
  final List<String> decoder;

  VocabMaps(this.encoder, this.decoder);
}

/// Loads vocabulary from HuggingFace tokenizer.json and creates a WordpieceTokenizer
/// This is designed for multilingual MiniLM models that use SentencePiece/WordPiece tokenization
class MultilingualTokenizerLoader {
  /// Load vocabulary from tokenizer.json file
  /// Returns encoder (token -> id) and decoder (id -> token) maps
  static Future<VocabMaps> loadFromTokenizerJson(
    String tokenizerJsonPath,
  ) async {
    final file = File(tokenizerJsonPath);
    if (!await file.exists()) {
      throw FileSystemException('Tokenizer JSON not found', tokenizerJsonPath);
    }

    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    // Extract vocabulary from tokenizer.json
    // The structure varies, but typically has 'model' -> 'vocab' or 'added_tokens'
    final Map<String, int> encoder = {};
    final List<String> decoder = [];

    // Try to get vocab from model.vocab
    // Vocab can be either a Map (token -> id) or List (indexed tokens)
    if (json.containsKey('model')) {
      final model = json['model'] as Map<String, dynamic>;
      if (model.containsKey('vocab')) {
        final vocab = model['vocab'];
        if (vocab is Map) {
          // Dictionary format: {token: id}
          vocab.forEach((token, id) {
            final tokenId = id is int ? id : int.parse(id.toString());
            encoder[token.toString()] = tokenId;
            while (decoder.length <= tokenId) {
              decoder.add('');
            }
            decoder[tokenId] = token.toString();
          });
        } else if (vocab is List) {
          // List format: can be either [token0, token1, ...] or [[token, score], ...]
          for (var i = 0; i < vocab.length; i++) {
            final item = vocab[i];
            String token;
            if (item is List && item.isNotEmpty) {
              // Format: [[token, score], ...] - take first element as token
              token = item[0].toString();
            } else {
              // Format: [token0, token1, ...]
              token = item.toString();
            }
            encoder[token] = i;
            while (decoder.length <= i) {
              decoder.add('');
            }
            decoder[i] = token;
          }
        }
      }
    }

    // Also check added_tokens for special tokens
    if (json.containsKey('added_tokens')) {
      final addedTokens = json['added_tokens'] as List<dynamic>;
      for (final tokenInfo in addedTokens) {
        final tokenMap = tokenInfo as Map<String, dynamic>;
        final content = tokenMap['content'] as String;
        final id = tokenMap['id'] as int;
        encoder[content] = id;
        while (decoder.length <= id) {
          decoder.add('');
        }
        decoder[id] = content;
      }
    }

    if (encoder.isEmpty) {
      throw FormatException('Could not extract vocabulary from tokenizer.json');
    }

    return VocabMaps(encoder, decoder);
  }

  /// Create a WordpieceTokenizer from vocabulary maps
  static WordpieceTokenizer createTokenizer({
    required Map<String, int> encoder,
    required List<String> decoder,
    String unkString = '[UNK]',
    int unkToken = 100,
    int startToken = 101,
    int endToken = 102,
    int maxInputTokens = 128,
    int maxInputCharsPerWord = 100,
  }) {
    return WordpieceTokenizer(
      encoder: encoder,
      decoder: decoder,
      unkString: unkString,
      unkToken: unkToken,
      startToken: startToken,
      endToken: endToken,
      maxInputTokens: maxInputTokens,
      maxInputCharsPerWord: maxInputCharsPerWord,
    );
  }

  /// Load vocabulary from a simple vocab.txt file (one token per line)
  /// Format: Each line is a token, line number (0-indexed) is the token ID
  /// Special tokens should be at the beginning:
  ///   Line 0: <pad> or [PAD]
  ///   Line 1: <unk> or [UNK]
  ///   Line 2: <s> or [CLS]
  ///   Line 3: </s> or [SEP]
  static Future<VocabMaps> loadVocabFromTxt(
    String vocabTxtPath,
  ) async {
    final file = File(vocabTxtPath);
    if (!await file.exists()) {
      throw FileSystemException('Vocab file not found', vocabTxtPath);
    }

    final lines = await file.readAsLines();
    final Map<String, int> encoder = {};
    final List<String> decoder = [];

    for (var i = 0; i < lines.length; i++) {
      final token = lines[i].trim();
      if (token.isNotEmpty) {
        encoder[token] = i;
        while (decoder.length <= i) {
          decoder.add('');
        }
        decoder[i] = token;
      }
    }

    if (encoder.isEmpty) {
      throw FormatException('Vocabulary file is empty or invalid');
    }

    return VocabMaps(encoder, decoder);
  }

  /// Load tokenizer from tokenizer.json (HuggingFace format) and create WordpieceTokenizer
  ///
  /// NOTE: tokenizer.json comes from HuggingFace model repositories.
  /// For custom vocabularies (like French-Fula), use loadFromVocabTxt() instead.
  static Future<WordpieceTokenizer> loadTokenizer(
    String tokenizerJsonPath, {
    String unkString = '[UNK]',
    int? unkToken,
    int? startToken,
    int? endToken,
    int maxInputTokens = 128,
    int maxInputCharsPerWord = 100,
  }) async {
    final vocab = await loadFromTokenizerJson(tokenizerJsonPath);

    // Try to find special tokens from the vocabulary
    final foundUnkToken =
        unkToken ?? vocab.encoder[unkString] ?? vocab.encoder['<unk>'] ?? 3;
    final foundStartToken =
        startToken ?? vocab.encoder['<s>'] ?? vocab.encoder['[CLS]'] ?? 0;
    final foundEndToken =
        endToken ?? vocab.encoder['</s>'] ?? vocab.encoder['[SEP]'] ?? 2;

    return createTokenizer(
      encoder: vocab.encoder,
      decoder: vocab.decoder,
      unkString: unkString,
      unkToken: foundUnkToken,
      startToken: foundStartToken,
      endToken: foundEndToken,
      maxInputTokens: maxInputTokens,
      maxInputCharsPerWord: maxInputCharsPerWord,
    );
  }

  /// Load tokenizer from a simple vocab.txt file (for custom vocabularies like French-Fula)
  ///
  /// Format: One token per line, line number is the token ID
  /// Example vocab.txt:
  ///   <pad>
  ///   <unk>
  ///   <s>
  ///   </s>
  ///   bonjour
  ///   hello
  ///   ...
  ///
  /// Special tokens (required):
  ///   - <pad> or [PAD] at line 0 (padding token)
  ///   - <unk> or [UNK] at line 1 (unknown token)
  ///   - <s> or [CLS] at line 2 (start token)
  ///   - </s> or [SEP] at line 3 (end token)
  static Future<WordpieceTokenizer> loadFromVocabTxt(
    String vocabTxtPath, {
    String unkString = '<unk>',
    int? unkToken,
    int? startToken,
    int? endToken,
    int maxInputTokens = 128,
    int maxInputCharsPerWord = 100,
  }) async {
    final vocab = await loadVocabFromTxt(vocabTxtPath);

    // Find special tokens (typically at positions 0-3)
    final foundUnkToken =
        unkToken ?? vocab.encoder['<unk>'] ?? vocab.encoder['[UNK]'] ?? 1;
    final foundStartToken =
        startToken ?? vocab.encoder['<s>'] ?? vocab.encoder['[CLS]'] ?? 2;
    final foundEndToken =
        endToken ?? vocab.encoder['</s>'] ?? vocab.encoder['[SEP]'] ?? 3;

    return createTokenizer(
      encoder: vocab.encoder,
      decoder: vocab.decoder,
      unkString: unkString,
      unkToken: foundUnkToken,
      startToken: foundStartToken,
      endToken: foundEndToken,
      maxInputTokens: maxInputTokens,
      maxInputCharsPerWord: maxInputCharsPerWord,
    );
  }
}

