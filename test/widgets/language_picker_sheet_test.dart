import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:languages_dart/languages_dart.dart';
import 'package:malinali/widgets/language_picker_sheet.dart';

void main() {
  // Language(localeIntl, nameEn, name)
  final pulaar = Language(Languages.fulah.localeIntl, 'Fulah', 'Pulaar');

  test('languageMatchesQuery matches native, English, and ISO', () {
    expect(languageMatchesQuery(pulaar, 'pula'), isTrue);
    expect(languageMatchesQuery(pulaar, 'fulah'), isTrue);
    expect(languageMatchesQuery(pulaar, 'ff'), isTrue);
    expect(languageMatchesQuery(pulaar, 'xyz'), isFalse);
  });

  test('languageDisplayName prefers native name', () {
    expect(languageDisplayName(pulaar), 'Pulaar');
    expect(languageDisplayName(Languages.french), isNotEmpty);
  });

  testWidgets('LanguagePickerSheet filters and returns selection', (
    WidgetTester tester,
  ) async {
    Language? picked;
    final languages = [
      Languages.french,
      Languages.english,
      pulaar,
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  picked = await LanguagePickerSheet.show(
                    context,
                    languages: languages,
                    selected: Languages.french,
                    title: 'Langue cible',
                    badgesFor: (lang) => LanguagePickerBadges(
                      translationAvailable: true,
                      translationReady:
                          languageIsoCode(lang) ==
                          languageIsoCode(Languages.french),
                      voskAvailable:
                          languageIsoCode(lang) ==
                          languageIsoCode(Languages.french),
                      voskReady: false,
                    ),
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Langue cible'), findsOneWidget);
    expect(find.text('Pulaar'), findsOneWidget);
    // Downloaded vs cloud icons (same as Modèles de traduction list).
    expect(find.byIcon(Icons.storage), findsOneWidget);
    expect(find.byIcon(Icons.cloud_download), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), 'pula');
    await tester.pumpAndSettle();

    expect(find.text('Pulaar'), findsOneWidget);
    expect(find.textContaining('English'), findsNothing);

    await tester.tap(find.text('Pulaar'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(languageDisplayName(picked!), 'Pulaar');
  });
}
