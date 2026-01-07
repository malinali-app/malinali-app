import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:malinali/services/generate_embeddings.dart';

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
          _statusMessage = 'Copying database...';
        });

        final selectedPath = result.files.single.path!;
        final appDir = await getApplicationDocumentsDirectory();
        final targetPath = '${appDir.path}/malinali.db';

        // Copy the selected database to malinali.db
        final sourceFile = File(selectedPath);
        final targetFile = File(targetPath);

        await sourceFile.copy(targetPath);
        print('✅ Database copied to: $targetPath');

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
        _statusMessage = 'Error: $e';
      });
    }
  }

  Future<void> _useDefaultDemo() async {
    try {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Loading default demo files from assets...';
      });

      // Load asset files
      final sourceContent = await rootBundle.loadString('assets/src_fra.txt');
      final targetContent = await rootBundle.loadString('assets/tgt_ful.txt');

      // Write to temporary files (generateEmbeddingsFromFiles expects file paths)
      final appDir = await getApplicationDocumentsDirectory();
      final tempDir = Directory('${appDir.path}/temp');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      final sourcePath = '${tempDir.path}/src_fra.txt';
      final targetPath = '${tempDir.path}/tgt_ful.txt';

      await File(sourcePath).writeAsString(sourceContent);
      await File(targetPath).writeAsString(targetContent);

      // Validate line counts
      setState(() {
        _statusMessage = 'Validating files...';
      });

      final sourceLines = sourceContent
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final targetLines = targetContent
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (sourceLines.length != targetLines.length) {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'Error: Files have different line counts.\n'
              'Source: ${sourceLines.length}, Target: ${targetLines.length}';
        });
        return;
      }

      // Generate embeddings
      setState(() {
        _statusMessage = 'Generating embeddings (this may take a while)...';
        _progressCurrent = 0;
        _progressTotal = sourceLines.length;
      });

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
                  'Generating embeddings: $current / $total (${((current / total) * 100).toStringAsFixed(1)}%)';
            });
          }
        },
      );

      // Clean up temporary files
      try {
        await File(sourcePath).delete();
        await File(targetPath).delete();
      } catch (e) {
        // Ignore cleanup errors
        print('Warning: Could not clean up temp files: $e');
      }

      setState(() {
        _statusMessage = '✅ Database created successfully!';
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
        _statusMessage = 'Error: $e';
      });
    }
  }

  Future<void> _selectTextFiles() async {
    try {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Please select source file (e.g., French)...';
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
        _statusMessage = 'Please select target file (e.g., Fula)...';
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
        _statusMessage = 'Validating files...';
      });

      final sourceFile = File(sourcePath);
      final targetFile = File(targetPath);

      final sourceContent = await sourceFile.readAsString();
      final targetContent = await targetFile.readAsString();

      final sourceLines = sourceContent
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final targetLines = targetContent
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (sourceLines.length != targetLines.length) {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'Error: Files have different line counts.\n'
              'Source: ${sourceLines.length}, Target: ${targetLines.length}';
        });
        return;
      }

      // Generate embeddings
      setState(() {
        _statusMessage = 'Generating embeddings (this may take a while)...';
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
                  'Generating embeddings: $current / $total (${((current / total) * 100).toStringAsFixed(1)}%)';
            });
          }
        },
      );

      setState(() {
        _statusMessage = '✅ Database created successfully!';
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
        _statusMessage = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Malinali Setup'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.translate,
                size: 64,
                color: Colors.blue,
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to Malinali',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose how you want to set up the translation database:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
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
                  label: const Text('Select SQLite Database'),
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
                  label: const Text('Select Source & Target Files (.txt)'),
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
                  label: const Text('Use Default Demo'),
                  style: ElevatedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              if (_statusMessage != null && _statusMessage!.startsWith('Error:'))
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _statusMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                    ),
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

