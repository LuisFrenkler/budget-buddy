// Widget smoke test. The full app needs Hive initialized, so the broad
// integration coverage lives in db_test.dart. Here we just verify that a
// formatted amount renders into the widget tree.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/utils/money.dart';

void main() {
  testWidgets('formatted amount renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Text(Money.format(123450)))),
    );
    expect(find.textContaining('1.234,50'), findsOneWidget);
  });
}
