#!/usr/bin/env dart
// ignore_for_file: avoid_print

/// Command-line tool to generate embeddings for translation datasets.
///
/// Usage:
///   dart run bin/generate_embeddings.dart \
///     --english assets/src_eng_license_free.txt \
///     --french assets/src_fra_license_free.txt \
///     --fula assets/tgt_ful_license_free.txt \
///     --output fula_translations.db \
///     --searcher-id fula
///
/// This tool:
/// 1. Loads text files (one translation per line)
/// 2. Generates embeddings using ONNX model
/// 3. Creates HybridFTSSearcher
/// 4. Saves to SQLite database
///
/// The generated database can then be:
/// - Copied to app assets (for distribution)
/// - Loaded directly in the app
/// - Exported to other formats

import 'dart:io';
import 'package:args/args.dart';
import 'package:ml_algo/src/persistence/sqlite_neighbor_search_store.dart';
import 'package:ml_algo/src/retrieval/hybrid_fts_searcher.dart';
import 'package:ml_algo/src/retrieval/translation_pair.dart';

// Note: This requires the embedding service, which needs Flutter
// For a pure Dart CLI tool, we'd need to refactor EmbeddingService
// to work without Flutter dependencies, or use a different approach.

Future<List<String>> loadTextFile(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw Exception('File not found: $filePath');
  }
  final content = await file.readAsString();
  return content.split('\n').where((line) => line.trim().isNotEmpty).toList();
}

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('english', abbr: 'e', help: 'Path to English source file')
    ..addOption('french', abbr: 'f', help: 'Path to French source file')
    ..addOption('fula', abbr: 't', help: 'Path to Fula target file')
    ..addOption('output', abbr: 'o', help: 'Output database path', defaultsTo: 'translations.db')
    ..addOption('searcher-id', abbr: 's', help: 'Searcher ID', defaultsTo: 'translations')
    ..addFlag('help', abbr: 'h', help: 'Show this help');

  final results = parser.parse(args);

  if (results['help'] == true) {
    print(parser.usage);
    return;
  }

  final englishPath = results['english'] as String?;
  final frenchPath = results['french'] as String?;
  final fulaPath = results['fula'] as String?;
  final outputPath = results['output'] as String;
  final searcherId = results['searcher-id'] as String;

  if (fulaPath == null) {
    print('Error: --fula (target file) is required');
    print(parser.usage);
    exit(1);
  }

  print('Generating embeddings for translation dataset...');
  print('Output: $outputPath');
  print('Searcher ID: $searcherId');
  print('');

  // Load files
  print('Loading text files...');
  final fulaLines = await loadTextFile(fulaPath);
  print('  Loaded ${fulaLines.length} Fula translations');

  List<String>? englishLines;
  if (englishPath != null) {
    englishLines = await loadTextFile(englishPath);
    print('  Loaded ${englishLines.length} English translations');
    if (englishLines.length != fulaLines.length) {
      throw Exception(
        'English file has ${englishLines.length} lines, but Fula has ${fulaLines.length}',
      );
    }
  }

  List<String>? frenchLines;
  if (frenchPath != null) {
    frenchLines = await loadTextFile(frenchPath);
    print('  Loaded ${frenchLines.length} French translations');
    if (frenchLines.length != fulaLines.length) {
      throw Exception(
        'French file has ${frenchLines.length} lines, but Fula has ${fulaLines.length}',
      );
    }
  }

  if (englishLines == null && frenchLines == null) {
    throw Exception('At least one source file (--english or --french) is required');
  }

  print('');
  print('⚠️  Note: This tool requires Flutter/ONNX integration.');
  print('   For now, use the Flutter app to generate embeddings.');
  print('   This CLI tool structure is ready for future implementation.');
  print('');
  print('To generate embeddings, use the app:');
  print('  flutter run');
  print('  (The app will automatically create the database on first run)');
}

