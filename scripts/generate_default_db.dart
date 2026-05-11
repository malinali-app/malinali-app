import 'dart:io';
import 'package:archive/archive_io.dart';

/// Script to generate the default malinali.db from combined_src.txt and combined_tgt.txt
/// and zip it for use in the app.
/// 
/// Run with: dart scripts/generate_default_db.dart
void main() async {
  final srcFile = File('assets/combined_src.txt');
  final tgtFile = File('assets/combined_tgt.txt');

  if (!await srcFile.exists() || !await tgtFile.exists()) {
    print('Error: Source or target text files not found in assets/');
    return;
  }

  print('Reading text files...');
  final srcLines = await srcFile.readAsLines();
  final tgtLines = await tgtFile.readAsLines();

  final count = srcLines.length < tgtLines.length ? srcLines.length : tgtLines.length;
  print('Processing $count translation pairs...');

  final dbPath = 'assets/malinali.db';
  final dbFile = File(dbPath);
  if (await dbFile.exists()) {
    await dbFile.delete();
  }

  // Create a temporary SQL file to speed up insertion
  final sqlFile = File('assets/temp_import.sql');
  final sink = sqlFile.openWrite();

  sink.writeln('PRAGMA synchronous = OFF;');
  sink.writeln('PRAGMA journal_mode = MEMORY;');
  sink.writeln('BEGIN TRANSACTION;');
  sink.writeln('''
    CREATE TABLE translations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source_text TEXT NOT NULL,
      target_text TEXT NOT NULL,
      source_lang TEXT,
      target_lang TEXT,
      is_user_input INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  ''');

  for (var i = 0; i < count; i++) {
    final src = srcLines[i].trim().replaceAll("'", "''");
    final tgt = tgtLines[i].trim().replaceAll("'", "''");
    if (src.isEmpty || tgt.isEmpty) continue;

    sink.writeln(
      "INSERT INTO translations (source_text, target_text, source_lang, target_lang) "
      "VALUES ('$src', '$tgt', 'French', 'Fula');"
    );
  }

  sink.writeln('COMMIT;');
  await sink.close();

  print('Importing into SQLite...');
  final result = await Process.run('sqlite3', [dbPath, '.read assets/temp_import.sql']);

  if (result.exitCode != 0) {
    print('Error importing into SQLite: ${result.stderr}');
    return;
  }
  
  print('✅ Successfully created $dbPath');
  
  // Clean up SQL file
  await sqlFile.delete();

  print('Zipping database...');
  final zipPath = 'assets/malinali.db.zip';
  final encoder = ZipFileEncoder();
  encoder.create(zipPath);
  encoder.addFile(dbFile);
  encoder.close();

  if (await File(zipPath).exists()) {
    print('✅ Successfully created $zipPath');
    // Optional: delete the unzipped db to keep assets clean
    // await dbFile.delete();
  } else {
    print('Error creating zip file');
  }

  print('\nDone! The app will now use this data when "Use Default Demo" is clicked.');
}
