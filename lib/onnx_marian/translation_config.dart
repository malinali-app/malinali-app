/// Decode hyperparameters matching Malinali street-mode / HuggingFace Marian.
class OnnxTranslationConfig {
  const OnnxTranslationConfig({
    required this.numBeams,
    required this.maxNewTokens,
    required this.lengthPenalty,
    required this.noRepeatNgramSize,
  });

  final int numBeams;
  final int maxNewTokens;
  final double lengthPenalty;
  final int noRepeatNgramSize;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnnxTranslationConfig &&
          numBeams == other.numBeams &&
          maxNewTokens == other.maxNewTokens &&
          lengthPenalty == other.lengthPenalty &&
          noRepeatNgramSize == other.noRepeatNgramSize;

  @override
  int get hashCode =>
      Object.hash(numBeams, maxNewTokens, lengthPenalty, noRepeatNgramSize);
}

/// Interactive on-device defaults (beams=2 / 24 new tokens).
const OnnxTranslationConfig kOnnxStreetTranslationConfig = OnnxTranslationConfig(
  numBeams: 2,
  maxNewTokens: 24,
  lengthPenalty: 1.2,
  noRepeatNgramSize: 3,
);
