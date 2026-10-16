import 'package:flutter/material.dart';
import 'package:malinali/services/local_voice_pairs.dart';
import 'package:malinali/theme/malinali_chrome.dart';

/// User confirmed a local pair, or asked to open language setup.
class VoicePairDialogResult {
  const VoicePairDialogResult.confirmed({
    required this.sourceIso,
    required this.targetIso,
  }) : openSetup = false;

  const VoicePairDialogResult.openSetup()
      : openSetup = true,
        sourceIso = null,
        targetIso = null;

  final bool openSetup;
  final String? sourceIso;
  final String? targetIso;
}

/// Ask which on-device pair should translate this note.
Future<VoicePairDialogResult?> showVoicePairConfirmDialog({
  required BuildContext context,
  required List<LocalVoicePair> pairs,
  String? initialSource,
  String? initialTarget,
}) {
  return showDialog<VoicePairDialogResult>(
    context: context,
    builder: (context) {
      if (pairs.isEmpty) {
        return AlertDialog(
          title: const Text('Aucun modèle vocal'),
          content: const Text(
            'Aucun couple de langues n’est disponible sur cet appareil.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                const VoicePairDialogResult.openSetup(),
              ),
              child: const Text('Choisir les langues'),
            ),
          ],
        );
      }
      return _PairDialog(
        pairs: pairs,
        initialSource: initialSource,
        initialTarget: initialTarget,
      );
    },
  );
}

class _PairDialog extends StatefulWidget {
  const _PairDialog({
    required this.pairs,
    this.initialSource,
    this.initialTarget,
  });

  final List<LocalVoicePair> pairs;
  final String? initialSource;
  final String? initialTarget;

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  late String _sourceIso;
  late String _targetIso;

  @override
  void initState() {
    super.initState();
    final sources = _sources;
    final preferred = widget.initialSource?.toLowerCase();
    _sourceIso = sources.containsKey(preferred) ? preferred! : sources.keys.first;
    _targetIso = _targetFor(_sourceIso);
  }

  Map<String, String> get _sources {
    final out = <String, String>{};
    for (final pair in widget.pairs) {
      out.putIfAbsent(pair.sourceIso, () => pair.sourceLabel);
    }
    return out;
  }

  List<LocalVoicePair> get _targets =>
      widget.pairs.where((pair) => pair.sourceIso == _sourceIso).toList();

  String _targetFor(String sourceIso) {
    final targets = widget.pairs.where((pair) => pair.sourceIso == sourceIso);
    final preferred = widget.initialTarget?.toLowerCase();
    for (final pair in targets) {
      if (pair.targetIso == preferred) return pair.targetIso;
    }
    return targets.first.targetIso;
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    final targets = _targets;
    return AlertDialog(
      title: const Text('Langues de cette note'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Je parle',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('source-$_sourceIso'),
              initialValue: _sourceIso,
              items: [
                for (final entry in sources.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _sourceIso = value;
                  _targetIso = _targetFor(value);
                });
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Traduire vers',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('target-$_sourceIso-$_targetIso'),
              initialValue: _targetIso,
              items: [
                for (final pair in targets)
                  DropdownMenuItem(
                    value: pair.targetIso,
                    child: Text(pair.targetLabel),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _targetIso = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: MalinaliChrome.yellowBorder,
            foregroundColor: MalinaliChrome.blueBg,
          ),
          onPressed: () => Navigator.pop(
            context,
            VoicePairDialogResult.confirmed(
              sourceIso: _sourceIso,
              targetIso: _targetIso,
            ),
          ),
          child: const Text('Traduire'),
        ),
      ],
    );
  }
}
