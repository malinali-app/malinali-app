import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:malinali/pages/byo_marian_page.dart';
import 'package:malinali/services/african_helsinki_models.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:url_launcher/url_launcher.dart';

class TranslationSettingsPage extends StatefulWidget {
  final TranslationModelService modelService;
  final TranslationModel? selectedModel;

  const TranslationSettingsPage({
    super.key,
    required this.modelService,
    this.selectedModel,
  });

  @override
  State<TranslationSettingsPage> createState() => _TranslationSettingsPageState();
}

class _TranslationSettingsPageState extends State<TranslationSettingsPage> {
  List<TranslationModel> _allModels = [];
  List<TranslationModel> _filteredModels = [];
  bool _loading = true;
  String _searchQuery = '';
  bool _searchSource = true; // true = search in source, false = search in target
  bool _onlyDownloaded = false;
  Map<String, bool> _downloadedStatus = {};

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      final models = await widget.modelService.fetchAllAvailableModels();

      final status = <String, bool>{};
      for (final model in models) {
        status[model.modelId] = await widget.modelService.isModelDownloaded(model);
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
              SnackBar(
                content: Text('Erreur: $e'),
                action: SnackBarAction(
                  label: 'Copier',
                  onPressed: () => Clipboard.setData(ClipboardData(text: e.toString())),
                ),
              ),
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

  Future<void> _openByo() async {
    final model = await Navigator.push<TranslationModel>(
      context,
      MaterialPageRoute(
        builder: (_) => ByoMarianPage(modelService: widget.modelService),
      ),
    );
    if (!mounted) return;
    if (model != null) {
      Navigator.pop(context, model);
      return;
    }
    await _loadModels();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modèles'),
        actions: [
          TextButton.icon(
            onPressed: _openByo,
            icon: const Icon(Icons.auto_awesome, size: 20),
            label: const Text('Mon modèle'),
            style: TextButton.styleFrom(
              foregroundColor: MalinaliChrome.yellowBorder,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              style: const TextStyle(color: MalinaliChrome.onBlue),
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
                const Text(
                  'Filtrer par : ',
                  style: TextStyle(color: MalinaliChrome.onBlue),
                ),
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
                const Text(
                  'Téléchargé',
                  style: TextStyle(
                    fontSize: 12,
                    color: MalinaliChrome.mutedOnBlue,
                  ),
                ),
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
                    ? const Center(
                        child: Text(
                          'Aucun modèle trouvé',
                          style: TextStyle(color: MalinaliChrome.mutedOnBlue),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredModels.length,
                        itemBuilder: (context, index) {
                          final model = _filteredModels[index];
                          final isSelected =
                              widget.selectedModel?.modelId == model.modelId;
                          final isDownloaded =
                              _downloadedStatus[model.modelId] ?? false;

                          return ListTile(
                            tileColor: model.isCustom
                                ? MalinaliChrome.customPanel
                                : null,
                            leading: Icon(
                              model.isAsset || isDownloaded
                                  ? Icons.storage
                                  : Icons.cloud_download,
                              color: isSelected
                                  ? MalinaliChrome.yellowBorder
                                  : MalinaliChrome.mutedOnBlue,
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
                                      color: MalinaliChrome.onBlue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(model.displayEnglishName),
                                Text(model.modelId),
                                if (model.qualityHint != null &&
                                    model.qualityHint!.isNotEmpty)
                                  InkWell(
                                    onTap: _launchBleuPaper,
                                    child: Text(
                                      model.qualityHint!,
                                      style: const TextStyle(
                                        color: MalinaliChrome.blueChip,
                                        decoration: TextDecoration.underline,
                                        decorationColor: MalinaliChrome.blueChip,
                                      ),
                                    ),
                                  ),
                              ],
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
                                  const Icon(
                                    Icons.check,
                                    color: MalinaliChrome.yellowBorder,
                                  ),
                              ],
                            ),
                            onTap: () async {
                              if (model.isAsset || isSelected || isDownloaded) {
                                Navigator.pop(context, model);
                                return;
                              }

                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    title: const Text('Téléchargement requis'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Le modèle de traduction pour ${model.displayName} doit être téléchargé'
                                          ' (${model.downloadSizeHint ?? 'environ 150 Mo'}).',
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'Ne quittez pas l\'écran et ne mettez pas l\'application en arrière-plan pendant le téléchargement.',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent),
                                        ),
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
                              if (confirm != true || !context.mounted) return;
                              Navigator.pop(context, model);
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
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching HF: $e');
    }
  }

  Future<void> _launchBleuPaper() async {
    final url = Uri.parse(kBleuPaperUrl);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching BLEU paper: $e');
    }
  }
}
