import 'package:flutter/material.dart';
import 'package:languages_dart/languages_dart.dart';

/// Badge hints for a language row (offline MT / speech).
class LanguagePickerBadges {
  const LanguagePickerBadges({
    this.translationReady = false,
    this.translationAvailable = false,
    this.voskReady = false,
    this.voskAvailable = false,
  });

  final bool translationReady;
  final bool translationAvailable;
  final bool voskReady;
  final bool voskAvailable;
}

String languageDisplayName(Language language) {
  if (language.name.isNotEmpty) return language.name;
  if (language.nameEn.isNotEmpty) return language.nameEn;
  return language.localeIntl.locale.languageCode;
}

String languageIsoCode(Language language) =>
    language.localeIntl.locale.languageCode;

bool languageMatchesQuery(Language language, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final iso = languageIsoCode(language).toLowerCase();
  return language.name.toLowerCase().contains(q) ||
      language.nameEn.toLowerCase().contains(q) ||
      iso.contains(q);
}

/// Malinali-styled searchable language picker (modal bottom sheet).
class LanguagePickerSheet extends StatefulWidget {
  const LanguagePickerSheet({
    super.key,
    required this.languages,
    this.selected,
    this.title = 'Choisir une langue',
    this.badgesFor,
  });

  final List<Language> languages;
  final Language? selected;
  final String title;
  final LanguagePickerBadges Function(Language language)? badgesFor;

  static Future<Language?> show(
    BuildContext context, {
    required List<Language> languages,
    Language? selected,
    String title = 'Choisir une langue',
    LanguagePickerBadges Function(Language language)? badgesFor,
  }) {
    return showModalBottomSheet<Language>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => LanguagePickerSheet(
        languages: languages,
        selected: selected,
        title: title,
        badgesFor: badgesFor,
      ),
    );
  }

  @override
  State<LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<LanguagePickerSheet> {
  final _searchController = TextEditingController();
  late List<Language> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = List<Language>.from(widget.languages);
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final q = _searchController.text;
    setState(() {
      _filtered = widget.languages
          .where((l) => languageMatchesQuery(l, q))
          .toList();
    });
  }

  bool _isSelected(Language language) {
    final selected = widget.selected;
    if (selected == null) return false;
    return languageIsoCode(language) == languageIsoCode(selected);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontFamily: 'NotoSans',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(fontFamily: 'NotoSans', fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Rechercher (nom, anglais, code ISO)…',
                hintStyle: TextStyle(
                  fontFamily: 'NotoSans',
                  color: Colors.grey.shade500,
                ),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF2563EB)),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      'Aucune langue trouvée',
                      style: TextStyle(
                        fontFamily: 'NotoSans',
                        color: Colors.grey.shade600,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Colors.grey.shade200,
                    ),
                    itemBuilder: (context, index) {
                      final language = _filtered[index];
                      final selected = _isSelected(language);
                      final badges =
                          widget.badgesFor?.call(language) ??
                          const LanguagePickerBadges();
                      final native = languageDisplayName(language);
                      final english = language.nameEn;
                      final iso = languageIsoCode(language);

                      return ListTile(
                        selected: selected,
                        selectedTileColor: const Color(0xFFEFF6FF),
                        leading: CircleAvatar(
                          backgroundColor: selected
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFE2E8F0),
                          foregroundColor:
                              selected ? Colors.white : const Color(0xFF1E3A8A),
                          child: Text(
                            native.isEmpty
                                ? '?'
                                : native.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              fontFamily: 'NotoSans',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(
                          native,
                          style: const TextStyle(
                            fontFamily: 'NotoSans',
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        subtitle: Text(
                          [
                            if (english.isNotEmpty && english != native) english,
                            iso,
                          ].join(' · '),
                          style: TextStyle(
                            fontFamily: 'NotoSans',
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (badges.translationReady ||
                                badges.translationAvailable)
                              _BadgeIcon(
                                icon: Icons.translate,
                                ready: badges.translationReady,
                                tooltip: badges.translationReady
                                    ? 'Traduction hors-ligne prête'
                                    : 'Modèle de traduction disponible',
                              ),
                            if (badges.voskReady || badges.voskAvailable) ...[
                              const SizedBox(width: 6),
                              _BadgeIcon(
                                icon: Icons.mic,
                                ready: badges.voskReady,
                                tooltip: badges.voskReady
                                    ? 'Saisie vocale prête'
                                    : 'Saisie vocale disponible',
                              ),
                            ],
                            if (selected) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF2563EB),
                              ),
                            ],
                          ],
                        ),
                        onTap: () => Navigator.pop(context, language),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({
    required this.icon,
    required this.ready,
    required this.tooltip,
  });

  final IconData icon;
  final bool ready;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Icon(
        icon,
        size: 18,
        color: ready ? Colors.green : const Color(0xFF2563EB),
      ),
    );
  }
}
