import 'package:flutter/material.dart';
import 'package:malinali/pages/transcription_settings_page.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:malinali/services/whisper_speech_service.dart';
import 'package:malinali/services/whisper_specialist_models.dart';
import 'package:malinali/theme/malinali_chrome.dart';

/// Choice popped back to the translate screen.
class SpeechSettingsResult {
  const SpeechSettingsResult.whisper({this.specialist}) : vosk = null;

  const SpeechSettingsResult.vosk(this.vosk) : specialist = null;

  /// Null means Whisper stays the microphone (tiny or [specialist]).
  final VoskModel? vosk;

  /// Null with null [vosk] means multilingual Whisper tiny (English translate).
  final WhisperSpecialistPack? specialist;

  bool get useWhisper => vosk == null;

  bool get useDefaultWhisper => vosk == null && specialist == null;
}

/// Default speech engine (Whisper tiny), specialist packs, plus Vosk.
class SpeechSettingsPage extends StatefulWidget {
  const SpeechSettingsPage({
    super.key,
    required this.voskService,
    this.selectedVoskModel,
    this.whisperService,
    this.selectedSpecialist,
  });

  final VoskModelService voskService;
  final VoskModel? selectedVoskModel;
  final WhisperSpeechService? whisperService;
  final WhisperSpecialistPack? selectedSpecialist;

  @override
  State<SpeechSettingsPage> createState() => _SpeechSettingsPageState();
}

class _SpeechSettingsPageState extends State<SpeechSettingsPage> {
  late final WhisperSpeechService _whisper;
  bool _checking = true;
  bool _tinyDownloaded = false;
  bool _tinyDownloading = false;
  String? _tinyError;
  final Map<String, bool> _specialistDownloaded = {};
  final Map<String, bool> _specialistDownloading = {};
  final Map<String, String?> _specialistErrors = {};

  @override
  void initState() {
    super.initState();
    _whisper = widget.whisperService ?? WhisperSpeechService();
    _refresh();
  }

  Future<void> _refresh() async {
    final tinyPresent = await _whisper.isTinyDownloaded();
    final downloaded = <String, bool>{};
    for (final pack in kWhisperSpecialistPacks) {
      downloaded[pack.id] = await _whisper.isSpecialistDownloaded(pack);
    }
    if (!mounted) return;
    setState(() {
      _tinyDownloaded = tinyPresent;
      _specialistDownloaded
        ..clear()
        ..addAll(downloaded);
      _checking = false;
    });
  }

  Future<void> _downloadTiny() async {
    setState(() {
      _tinyDownloading = true;
      _tinyError = null;
    });
    try {
      await _whisper.ensureTinyModel();
      if (!mounted) return;
      setState(() {
        _tinyDownloaded = true;
        _tinyDownloading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tinyDownloading = false;
        _tinyError = e.toString();
      });
    }
  }

  Future<void> _downloadSpecialist(WhisperSpecialistPack pack) async {
    if (!pack.isDownloadable) return;
    setState(() {
      _specialistDownloading[pack.id] = true;
      _specialistErrors[pack.id] = null;
    });
    try {
      await _whisper.downloadSpecialist(pack);
      if (!mounted) return;
      setState(() {
        _specialistDownloaded[pack.id] = true;
        _specialistDownloading[pack.id] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _specialistDownloading[pack.id] = false;
        _specialistErrors[pack.id] = e.toString();
      });
    }
  }

  Future<void> _openVosk() async {
    final model = await Navigator.push<VoskModel>(
      context,
      MaterialPageRoute(
        builder: (context) => TranscriptionSettingsPage(
          voskService: widget.voskService,
          selectedModel: widget.selectedVoskModel,
        ),
      ),
    );
    if (model != null && mounted) {
      Navigator.pop(context, SpeechSettingsResult.vosk(model));
    }
  }

  bool get _tinySelected =>
      widget.selectedSpecialist == null && widget.selectedVoskModel == null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saisie vocale')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: MalinaliChrome.blueAction.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.multitrack_audio,
                          color: MalinaliChrome.yellowBorder,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Whisper tiny',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (_checking)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          _tinyDownloaded ? Icons.storage : Icons.cloud_download,
                          color: _tinyDownloaded
                              ? MalinaliChrome.success
                              : MalinaliChrome.mutedOnBlue,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Microphone par défaut. La parole est traduite en anglais '
                    '(${WhisperSpeechService.downloadSizeHint}), puis Marian '
                    'traduit vers la langue cible.',
                    style: TextStyle(fontSize: 13),
                  ),
                  if (_tinySelected) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Sélectionné',
                      style: TextStyle(
                        fontSize: 12,
                        color: MalinaliChrome.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_tinyError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _tinyError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (!_tinyDownloaded)
                        TextButton.icon(
                          onPressed: _tinyDownloading ? null : _downloadTiny,
                          icon: _tinyDownloading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.download),
                          label: const Text('Télécharger'),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(
                          context,
                          const SpeechSettingsResult.whisper(),
                        ),
                        child: const Text('Utiliser Whisper tiny'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(
              'Modèles spécialisés (transcription)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              'Finetunes par langue : transcription seule, pas de traduction '
              'vers l’anglais. Whisper tiny reste le mode recommandé pour '
              'traduire ensuite avec Marian.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          for (final pack in kWhisperSpecialistPacks)
            _SpecialistPackCard(
              pack: pack,
              checking: _checking,
              downloaded: _specialistDownloaded[pack.id] == true,
              downloading: _specialistDownloading[pack.id] == true,
              selected: widget.selectedSpecialist?.id == pack.id,
              error: _specialistErrors[pack.id],
              onDownload: () => _downloadSpecialist(pack),
              onUse: pack.isDownloadable
                  ? () => Navigator.pop(
                        context,
                        SpeechSettingsResult.whisper(specialist: pack),
                      )
                  : null,
            ),
          Card(
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MalinaliChrome.yellowBorder.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.graphic_eq,
                  color: MalinaliChrome.yellowBorder,
                  size: 26,
                ),
              ),
              title: const Text(
                'Vosk',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: const Text(
                'Modèles vocaux par langue (reconnaissance, pas de traduction)',
                style: TextStyle(fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openVosk,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecialistPackCard extends StatelessWidget {
  const _SpecialistPackCard({
    required this.pack,
    required this.checking,
    required this.downloaded,
    required this.downloading,
    required this.selected,
    required this.error,
    required this.onDownload,
    required this.onUse,
  });

  final WhisperSpecialistPack pack;
  final bool checking;
  final bool downloaded;
  final bool downloading;
  final bool selected;
  final String? error;
  final VoidCallback onDownload;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    final available = pack.isDownloadable;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pack.labelFr,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (checking)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (!available)
                  const Icon(Icons.lock_outline, color: MalinaliChrome.mutedOnBlue)
                else
                  Icon(
                    downloaded ? Icons.storage : Icons.cloud_download,
                    color: downloaded
                        ? MalinaliChrome.success
                        : MalinaliChrome.mutedOnBlue,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              available
                  ? (pack.hasMarianOutbound
                      ? 'Transcription ${pack.iso.toUpperCase()} '
                          '(${pack.downloadSizeHint}). Source : ${pack.upstreamRepo}.'
                      : 'Transcription ${pack.iso.toUpperCase()} '
                          '(${pack.downloadSizeHint}). Pas de traduction vers '
                          'l’anglais. Source : ${pack.upstreamRepo}.')
                  : (pack.statusReason ??
                      'Modèle indisponible pour le moment.'),
              style: const TextStyle(fontSize: 13),
            ),
            if (pack.hasMarianOutbound && available) ...[
              const SizedBox(height: 4),
              const Text(
                'Marian peut ensuite traduire depuis cette langue si un '
                'modèle source→cible est téléchargé.',
                style: TextStyle(fontSize: 12),
              ),
            ],
            if (selected) ...[
              const SizedBox(height: 6),
              Text(
                'Sélectionné',
                style: TextStyle(
                  fontSize: 12,
                  color: MalinaliChrome.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ],
            if (available) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!downloaded)
                    TextButton.icon(
                      onPressed: downloading ? null : onDownload,
                      icon: downloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: const Text('Télécharger'),
                    ),
                  TextButton(
                    onPressed: onUse,
                    child: const Text('Utiliser'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
