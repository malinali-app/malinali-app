import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:malinali/services/generate_embeddings.dart';
import 'package:archive/archive.dart';

/// Initial setup screen that allows users to either:
/// 1. Select an existing SQLite database
/// 2. Select source and target .txt files to generate embeddings
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.onComplete});

  /// Callback called when setup is complete (database selected or created)
  final VoidCallback? onComplete;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _isProcessing = false;
  String? _statusMessage;
  int _progressCurrent = 0;
  int _progressTotal = 0;

  Future<void> _selectDatabase() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'sqlite'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _isProcessing = true;
          _statusMessage = 'Copie de la base de données...';
        });

        final selectedPath = result.files.single.path!;
        final appDir = await getApplicationDocumentsDirectory();
        final targetPath = '${appDir.path}/malinali.db';

        // Copy the selected database to malinali.db
        final sourceFile = File(selectedPath);
        final targetFile = File(targetPath);
        
        // Delete existing database if it exists (to ensure clean copy)
        if (await targetFile.exists()) {
          await targetFile.delete();
        }

        await sourceFile.copy(targetPath);
        final copiedStat = await File(targetPath).stat();
        print('✅ Database copied to: $targetPath');
        print('   Copied database size: ${copiedStat.size} bytes');

        // Call completion callback
        if (mounted) {
          if (widget.onComplete != null) {
            widget.onComplete!();
          } else {
            // Fallback: pop and let parent handle navigation
            Navigator.of(context).pop(true);
          }
        }
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Erreur : $e';
      });
    }
  }

  Future<void> _useDefaultDemo() async {
    try {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Chargement de la base de données...';
        _progressCurrent = 0;
        _progressTotal = 0;
      });

      // Load zipped database from assets
      final ByteData zipData = await rootBundle.load('assets/malinali.db.zip');
      final Uint8List zipBytes = zipData.buffer.asUint8List();

      // Decompress the zip file
      setState(() {
        _statusMessage = 'Décompression de la base de données...';
      });

      final Archive archive = ZipDecoder().decodeBytes(zipBytes);
      
      // Get the database file from the archive
      ArchiveFile? dbFileInArchive;
      for (final file in archive) {
        if (file.name == 'malinali.db' || file.name.endsWith('.db')) {
          dbFileInArchive = file;
          break;
        }
      }

      if (dbFileInArchive == null) {
        throw Exception('Database file not found in archive');
      }

      // Write database to app directory
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = '${appDir.path}/malinali.db';
      
      setState(() {
        _statusMessage = 'Copie de la base de données...';
      });

      final dbFile = File(dbPath);
      await dbFile.writeAsBytes(dbFileInArchive.content as List<int>);

      // Verify database was created
      if (!await dbFile.exists()) {
        throw Exception('Database file was not created at $dbPath');
      }
      final dbStat = await dbFile.stat();
      print('✅ Database extracted successfully at: $dbPath');
      print('   Database size: ${dbStat.size} bytes');
      print('   Database modified: ${dbStat.modified}');

      setState(() {
        _statusMessage = '✅ Base de données chargée avec succès !';
      });

      // Wait a moment to show success message
      await Future.delayed(const Duration(seconds: 1));

      // Call completion callback
      if (mounted) {
        if (widget.onComplete != null) {
          widget.onComplete!();
        } else {
          // Fallback: pop and let parent handle navigation
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Erreur : $e';
      });
    }
  }

  Future<void> _selectTextFiles() async {
    try {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Veuillez sélectionner le fichier source (ex. Français)...';
      });

      // Select source file
      final sourceResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (sourceResult == null || sourceResult.files.single.path == null) {
        setState(() {
          _isProcessing = false;
          _statusMessage = null;
        });
        return;
      }

      final sourcePath = sourceResult.files.single.path!;

      setState(() {
        _statusMessage = 'Veuillez sélectionner le fichier cible (ex. Pulaar)...';
      });

      // Select target file
      final targetResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (targetResult == null || targetResult.files.single.path == null) {
        setState(() {
          _isProcessing = false;
          _statusMessage = null;
        });
        return;
      }

      final targetPath = targetResult.files.single.path!;

      // Validate line counts
      setState(() {
        _statusMessage = 'Validation des fichiers...';
      });

      final sourceFile = File(sourcePath);
      final targetFile = File(targetPath);

      final sourceContent = await sourceFile.readAsString();
      final targetContent = await targetFile.readAsString();

      final sourceLines =
          sourceContent
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();
      final targetLines =
          targetContent
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();

      if (sourceLines.length != targetLines.length) {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'Erreur : Les fichiers ont un nombre de lignes différent.\n'
              'Source : ${sourceLines.length}, Cible : ${targetLines.length}';
        });
        return;
      }

      // Generate embeddings
      setState(() {
        _statusMessage = 'Génération des embeddings (cela peut prendre un moment)...';
        _progressCurrent = 0;
        _progressTotal = sourceLines.length;
      });

      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = '${appDir.path}/malinali.db';

      await generateEmbeddingsFromFiles(
        sourceFilePath: sourcePath,
        targetFilePath: targetPath,
        dbPath: dbPath,
        searcherId: 'fula',
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _progressCurrent = current;
              _progressTotal = total;
              _statusMessage =
                  'Génération des embeddings : $current / $total (${((current / total) * 100).toStringAsFixed(1)}%)';
            });
          }
        },
      );

      // Verify database was created
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        throw Exception('Database file was not created at $dbPath');
      }
      final dbStat = await dbFile.stat();
      print('✅ Database created successfully at: $dbPath');
      print('   Database size: ${dbStat.size} bytes');
      print('   Database modified: ${dbStat.modified}');

      setState(() {
        _statusMessage = '✅ Base de données créée avec succès !';
      });

      // Wait a moment to show success message
      await Future.delayed(const Duration(seconds: 1));

      // Call completion callback
      if (mounted) {
        if (widget.onComplete != null) {
          widget.onComplete!();
        } else {
          // Fallback: pop and let parent handle navigation
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Erreur : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Bienvenue dans Malinali',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choisissez comment configurer la base de données de traduction :',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 48),
              if (_statusMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _statusMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (_progressTotal > 0) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _progressCurrent / _progressTotal,
                          backgroundColor: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$_progressCurrent / $_progressTotal',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _selectDatabase,
                  icon: const Icon(Icons.storage),
                  label: const Text('Sélectionner une base de données SQLite'),
                  style: ElevatedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _selectTextFiles,
                  icon: const Icon(Icons.text_snippet),
                  label: const Text('Sélectionner des fichiers source/cible (.txt)'),
                  style: ElevatedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _useDefaultDemo,
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Utiliser la démo par défaut'),
                  style: ElevatedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              if (_statusMessage != null &&
                  _statusMessage!.startsWith('Erreur'))
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _statusMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
