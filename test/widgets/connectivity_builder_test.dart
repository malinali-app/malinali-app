import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malinali/widgets/connectivity_builder.dart';

void main() {
  group('FutureBuilder2', () {
    testWidgets('renders data when future succeeds', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FutureBuilder2<String>(
              callerName: 'testCaller',
              future: Future.value('success_data'),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Text(snapshot.data!);
                }
                return const CircularProgressIndicator();
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('success_data'), findsOneWidget);
    });

    testWidgets('reports error when future fails', (tester) async {
      final completer = Completer<String>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FutureBuilder2<String>(
              callerName: 'failedCaller',
              future: completer.future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                return const CircularProgressIndicator();
              },
            ),
          ),
        ),
      );

      completer.completeError(Exception('future_error'));
      await tester.pump();
      expect(tester.takeException(), isNotNull);

      expect(find.textContaining('future_error'), findsOneWidget);
    });
  });

  group('ConnectivityFutureBuilder', () {
    testWidgets('renders child or offline widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConnectivityFutureBuilder(
              const Text('online_content'),
              const Text('offline_content'),
            ),
          ),
        ),
      );

      // Initially _hasInternet is true
      expect(find.text('online_content'), findsOneWidget);
    });
  });
}
