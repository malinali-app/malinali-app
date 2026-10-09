import 'package:flutter/material.dart';
import 'package:malinali/pages/translate_page.dart';
import 'package:malinali/pages/vosk_transcription_page.dart';
import 'package:malinali/services/app_info.dart';
import 'package:malinali/services/marian_runtime.dart';
import 'package:malinali/services/translation_model_service.dart';
import 'package:malinali/services/vosk_model_service.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:marian_flutter/marian_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class MalinaliDrawer extends StatelessWidget {
  const MalinaliDrawer({
    super.key,
    this.onConversationTap,
  });

  final VoidCallback? onConversationTap;

  Future<void> _openWritten(BuildContext context) async {
    final modelService = TranslationModelService();
    final runtime = MarianRuntime.instance;
    MarianService? marian = runtime.marian;
    TranslationModel? model = runtime.model;

    if (marian == null || model == null) {
      final boot = await MarianRuntime.resolveBootModel(modelService);
      model = boot;
      if (boot.isAsset) {
        marian = await MarianService.loadFromAssets(assetFolder: boot.modelId);
      } else {
        final dir = await modelService.downloadModel(boot);
        marian = await MarianService.loadFromDirectory(dir.path);
      }
      runtime.attach(marian, boot);
      await MarianRuntime.saveLastSelectedModel(boot);
    }

    if (!context.mounted) return;
    Navigator.pop(context); // Close drawer

    // If already on translate page, don't push
    final route = ModalRoute.of(context);
    if (route?.settings.name == '/translate') return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: '/translate'),
        builder: (_) => TranslatePage(
          initialMarian: marian!,
          initialModel: model,
          modelService: modelService,
        ),
      ),
    );
  }

  void _openTranscription(BuildContext context) {
    Navigator.pop(context); // Close drawer
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: '/transcription'),
        builder: (_) => VoskTranscriptionPage(
          voskService: VoskModelService(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = ModalRoute.of(context)?.settings.name;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: MalinaliChrome.blueBg.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(32),
            bottomRight: Radius.circular(32),
          ),
          border: Border(
            right: BorderSide(
              color: MalinaliChrome.whiteBorder.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 40, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MalinaliChrome.blueAction.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Image.asset(
                        'assets/malinali_logo.jpg',
                        height: 48,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Malinali',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'Traduction universelle',
                      style: TextStyle(
                        color: MalinaliChrome.mutedOnBlue,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Divider(color: Colors.white10, height: 1),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _DrawerItem(
                      icon: Icons.chat_bubble_rounded,
                      title: 'Traduction vocale',
                      subtitle: 'Conversation bilingue',
                      color: MalinaliChrome.yellowBorder,
                      isSelected: currentPath == '/',
                      onTap: () {
                        Navigator.pop(context);
                        if (onConversationTap != null) {
                          onConversationTap!();
                        } else {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        }
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.translate_rounded,
                      title: 'Traduction écrite',
                      subtitle: 'Texte et documents',
                      color: MalinaliChrome.blueAction,
                      isSelected: currentPath == '/translate',
                      onTap: () => _openWritten(context),
                    ),
                    _DrawerItem(
                      icon: Icons.audio_file_rounded,
                      title: 'Transcription audio',
                      subtitle: 'Note vocale et fichiers',
                      color: MalinaliChrome.blueChip,
                      isSelected: currentPath == '/transcription',
                      onTap: () => _openTranscription(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    Text(
                      'v${AppInfo.version}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                      ),
                      color: Colors.white.withValues(alpha: 0.2),
                      onPressed: () => launchUrl(
                        Uri.parse('https://github.com/malinali-app/malinali-app'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isSelected = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected ? color : color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: isSelected ? Colors.white : color,
              size: 24,
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: isSelected ? Colors.white : MalinaliChrome.onBlue,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 16,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.7)
                  : MalinaliChrome.mutedOnBlue,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
