import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:malinali/malinali_app.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MalinaliApp());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
