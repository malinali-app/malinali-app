import 'dart:io';
import 'package:flutter/material.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

class TranslationSettingsPage extends StatefulWidget {
  final TranslationModelService modelService;
  final TranslationModel? selectedModel;
  final VoskModelService? voskService;

  const TranslationSettingsPage({
    super.key,
    required this.modelService,
    this.selectedModel,
    this.voskService,
  });

  @override
  State<TranslationSettingsPage> createState() => _TranslationSettingsPageState();
}

class _TranslationSettingsPageState extends State<TranslationSettingsPage> {
  List<TranslationModel> _allModels = [];
  List<TranslationModel> _filteredModels = [];
  List<VoskModel> _voskModels = [];
  bool _loading = true;
  String _searchQuery = '';
  bool _searchSource = true; // true = search in source, false = search in target
  bool _onlyDownloaded = false;
  Map<String, bool> _downloadedStatus = {};
  Map<String, bool> _voskDownloadedStatus = {};

  late final VoskModelService _voskService;

  @override
  void initState() {
    super.initState();
    _voskService = widget.voskService ?? VoskModelService();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      final models = await widget.modelService.fetchAllAvailableModels();
      final voskModels = await _voskService.fetchAllSmallModels();
      
      final docs = await getApplicationDocumentsDirectory();
      final String baseDir = Platform.isWindows
          ? 'Malinali_do_not_delete/marian_models'
          : 'marian_models';
      
      final status = <String, bool>{};
      for (final model in models) {
        if (model.isAsset) {
          status[model.modelId] = true;
          continue;
        }
        bool exists = false;
        try {
          final modelDir = Directory(
            p.join(docs.path, baseDir, model.modelId.replaceAll('/', '_')),
          );
          exists = await modelDir.exists();
          if (exists) {
            final mainFile = File(p.join(modelDir.path, 'model.safetensors'));
            exists = await mainFile.exists() && await mainFile.length() > 0;
          }
        } catch (_) {
          exists = false;
        }
        status[model.modelId] = exists;
      }

      final voskStatus = <String, bool>{};
      for (final vm in voskModels) {
        voskStatus[vm.name] = await _voskService.isModelDownloaded(vm);
      }

      if (mounted) {
        setState(() {
          _allModels = models;
          _voskModels = voskModels;
          _downloadedStatus = status;
          _voskDownloadedStatus = voskStatus;
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
    Iterable<TranslationModel> models = _allModels;

    if (_onlyDownloaded) {
      models = models.where((m) => _downloadedStatus[m.modelId] == true);
    }

    if (_searchQuery.isEmpty) {
      _filteredModels = models.toList();
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredModels = models.where((m) {
        if (_searchSource) {
          return m.sourceLang.name.toLowerCase().contains(query) ||
              m.sourceLang.nameEn.toLowerCase().contains(query) ||
              m.sourceLang.localeIntl.locale.languageCode.contains(query);
        } else {
          return m.targetLang.name.toLowerCase().contains(query) ||
              m.targetLang.nameEn.toLowerCase().contains(query) ||
              m.targetLang.localeIntl.locale.languageCode.contains(query);
        }
      }).toList();
    }
  }

  VoskModel? _matchingVoskModel(TranslationModel model) {
    return _voskService.findModelForLanguage(model.sourceLang, _voskModels);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modèles de traduction'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher une langue...',
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
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                const Text('Filtrer par : '),
                ChoiceChip(
                  label: const Text('Source'),
                  selected: _searchSource,
                  onSelected: (selected) {
                    setState(() {
                      _searchSource = true;
                      _applyFilter();
                    });
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Cible'),
                  selected: !_searchSource,
                  onSelected: (selected) {
                    setState(() {
                      _searchSource = false;
                      _applyFilter();
                    });
                  },
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
          const Divider(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredModels.isEmpty
                    ? const Center(child: Text('Aucun modèle trouvé'))
                    : ListView.builder(
                        itemCount: _filteredModels.length,
                        itemBuilder: (context, index) {
                          final model = _filteredModels[index];
                          final isSelected =
                              widget.selectedModel?.modelId == model.modelId;
                          final isDownloaded =
                              _downloadedStatus[model.modelId] ?? false;
                          final voskModel = _matchingVoskModel(model);
                          final hasVosk = voskModel != null;
                          final isVoskDownloaded =
                              hasVosk && (_voskDownloadedStatus[voskModel.name] ?? false);

                          return ListTile(
                            leading: Icon(
                              model.isAsset || isDownloaded
                                  ? Icons.storage
                                  : Icons.cloud_download,
                              color: isSelected ? Colors.blue : Colors.grey,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    model.displayName,
                                    style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (hasVosk)
                                  Tooltip(
                                    message: isVoskDownloaded
                                        ? 'Saisie vocale disponible et prête (${voskModel.langText})'
                                        : 'Saisie vocale disponible au téléchargement (${voskModel.langText})',
                                    child: Icon(
                                      Icons.mic,
                                      size: 18,
                                      color: isVoskDownloaded
                                          ? Colors.green
                                          : Colors.blue.shade300,
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              '${model.displayEnglishName}\n${model.modelId}${hasVosk ? ' • Voix: ${voskModel.langText}' : ''}',
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!model.isAsset)
                                  IconButton(
                                    icon: const Icon(Icons.info_outline),
                                    tooltip: 'Plus d\'infos',
                                    onPressed: () => _launchHF(model.modelId),
                                  ),
                                if (isSelected)
                                  const Icon(Icons.check, color: Colors.blue),
                              ],
                            ),
                            onTap: () async {
                              if (model.isAsset || isSelected || isDownloaded) {
                                Navigator.pop(context, model);
                                return;
                              }

                              bool downloadVoskAlso = false;
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) {
                                  return StatefulBuilder(
                                    builder: (context, setDialogState) {
                                      return AlertDialog(
                                        title: const Text('Téléchargement requis'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Le modèle de traduction pour ${model.displayName} doit être téléchargé (environ 150 Mo).',
                                            ),
                                            if (hasVosk && !isVoskDownloaded) ...[
                                              const SizedBox(height: 12),
                                              CheckboxListTile(
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(
                                                  'Télécharger aussi la saisie vocale pour ${voskModel.langText} (${voskModel.sizeText})',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                value: downloadVoskAlso,
                                                onChanged: (val) {
                                                  setDialogState(() {
                                                    downloadVoskAlso = val ?? false;
                                                  });
                                                },
                                              ),
                                            ],
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Annuler'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Télécharger'),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              );
                              if (confirm != true) return;

                              if (downloadVoskAlso && hasVosk) {
                                _voskService.downloadModel(voskModel).catchError((_) => '');
                              }

                              if (mounted) {
                                Navigator.pop(context, model);
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

  Future<void> _launchHF(String modelId) async {
    final url = Uri.parse('https://huggingface.co/$modelId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }
}
