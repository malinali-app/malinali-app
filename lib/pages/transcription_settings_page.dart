import 'package:flutter/material.dart';
import 'package:malinali/services/vosk_model_service.dart';

class TranscriptionSettingsPage extends StatefulWidget {
  final VoskModelService voskService;
  final VoskModel? selectedModel;

  const TranscriptionSettingsPage({
    super.key,
    required this.voskService,
    this.selectedModel,
  });

  @override
  State<TranscriptionSettingsPage> createState() =>
      _TranscriptionSettingsPageState();
}

class _TranscriptionSettingsPageState extends State<TranscriptionSettingsPage> {
  List<VoskModel> _allModels = [];
  List<VoskModel> _filteredModels = [];
  Map<String, bool> _downloadedStatus = {};
  final Map<String, double> _downloadProgress = {};
  bool _loading = true;
  String _searchQuery = '';
  bool _onlyDownloaded = false;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      final models = await widget.voskService.fetchAllSmallModels();
      final status = <String, bool>{};

      for (final model in models) {
        status[model.name] = await widget.voskService.isModelDownloaded(model);
      }

      if (mounted) {
        setState(() {
          _allModels = models;
          _downloadedStatus = status;
          _applyFilter();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur: $e')),
            );
          }
        });
      }
    }
  }

  void _applyFilter() {
    Iterable<VoskModel> models = _allModels;

    if (_onlyDownloaded) {
      models = models.where((m) => _downloadedStatus[m.name] == true);
    }

    if (_searchQuery.isEmpty) {
      _filteredModels = models.toList();
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredModels = models.where((m) {
        return m.langText.toLowerCase().contains(query) ||
            m.lang.toLowerCase().contains(query) ||
            m.name.toLowerCase().contains(query);
      }).toList();
    }
  }

  Future<void> _downloadModel(VoskModel model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Télécharger ${model.langText}'),
        content: Text(
          'Voulez-vous télécharger le modèle vocal pour ${model.langText} (${model.sizeText}) ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Télécharger'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _downloadProgress[model.name] = 0.0;
    });

    try {
      await widget.voskService.downloadModel(
        model,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() {
              _downloadProgress[model.name] = received / total;
            });
          }
        },
      );

      final isDownloaded = await widget.voskService.isModelDownloaded(model);
      if (mounted) {
        setState(() {
          _downloadProgress.remove(model.name);
          _downloadedStatus[model.name] = isDownloaded;
          _applyFilter();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Modèle vocal ${model.langText} prêt')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadProgress.remove(model.name);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du téléchargement: $e')),
        );
      }
    }
  }

  Future<void> _deleteModel(VoskModel model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le modèle'),
        content: Text(
          'Voulez-vous supprimer le modèle vocal ${model.langText} (${model.sizeText}) pour libérer de l\'espace ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await widget.voskService.deleteModel(model);
      if (mounted) {
        setState(() {
          _downloadedStatus[model.name] = false;
          _applyFilter();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Modèle ${model.langText} supprimé')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la suppression: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modèles de transcription'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher une langue vocale...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _applyFilter();
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _applyFilter();
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Text(
                  '${_filteredModels.length} modèle(s) VOSK small',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                const Text('Téléchargé', style: TextStyle(fontSize: 12)),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _onlyDownloaded,
                    onChanged: (value) {
                      setState(() {
                        _onlyDownloaded = value;
                        _applyFilter();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredModels.isEmpty
                    ? const Center(child: Text('Aucun modèle vocal trouvé'))
                    : ListView.builder(
                        itemCount: _filteredModels.length,
                        itemBuilder: (context, index) {
                          final model = _filteredModels[index];
                          final isSelected =
                              widget.selectedModel?.name == model.name;
                          final isDownloaded =
                              _downloadedStatus[model.name] ?? false;
                          final progress = _downloadProgress[model.name];
                          final isDownloading = progress != null;

                          return ListTile(
                            leading: Icon(
                              model.isAsset || isDownloaded
                                  ? Icons.mic
                                  : Icons.mic_none,
                              color: isSelected
                                  ? Colors.blue
                                  : (model.isAsset || isDownloaded
                                      ? Colors.green
                                      : Colors.grey),
                            ),
                            title: Text(
                              model.langText.isEmpty ? model.lang : model.langText,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${model.name} • ${model.sizeText}'),
                                if (model.isAsset)
                                  const Text(
                                    'Intégré à l\'application',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 12,
                                    ),
                                  )
                                else if (isDownloading)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: LinearProgressIndicator(
                                      value: progress > 0 ? progress : null,
                                    ),
                                  )
                                else if (isDownloaded)
                                  const Text(
                                    'Téléchargé (prêt)',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: isDownloading
                                ? Text(
                                    '${(progress * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(fontSize: 12),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isDownloaded && !model.isAsset)
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.redAccent,
                                          ),
                                          tooltip: 'Supprimer',
                                          onPressed: () => _deleteModel(model),
                                        ),
                                      if (!isDownloaded && !model.isAsset)
                                        IconButton(
                                          icon: const Icon(Icons.cloud_download),
                                          tooltip: 'Télécharger',
                                          onPressed: () => _downloadModel(model),
                                        ),
                                      if (isSelected)
                                        const Icon(Icons.check, color: Colors.blue),
                                    ],
                                  ),
                            onTap: () {
                              if (isDownloaded || model.isAsset) {
                                Navigator.pop(context, model);
                              } else {
                                _downloadModel(model);
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
