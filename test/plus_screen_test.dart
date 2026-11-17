import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/screens/plus_screen.dart';
import 'package:budget_buddy/services/plus_service.dart';

void main() {
  testWidgets('Plus pitch shows the free quota and Buddy without a limit',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PlusScreen()));

    expect(find.text('Ahead Plus'), findsOneWidget);
    expect(find.text('Ahead ohne Limit'), findsOneWidget);
    expect(find.text('${PlusService.freeAiQuestions}/Monat'), findsOneWidget);
    expect(find.text('${PlusService.freeReceiptScans}/Monat'), findsOneWidget);
    expect(find.text('${PlusService.freeGoals}'), findsOneWidget);
    expect(find.text('ohne Limit'), findsNWidgets(3));
    expect(find.text('Plus starten'), findsOneWidget);
  });
}
