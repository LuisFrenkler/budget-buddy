import 'dart:io';
import 'package:budget_buddy/screens/add_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('addrefund').path);
    for (final name in ['transactions', 'settings', 'recurring', 'badges']) {
      await Hive.openBox(name);
    }
  });

  testWidgets('a refund is entered under the spending categories, on a phone-sized screen', (tester) async {
    tester.view.physicalSize = const Size(750, 1624);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('de', 'DE'),
      supportedLocales: [Locale('de', 'DE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: AddScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Erstattung'), findsOneWidget);

    await tester.tap(find.text('Erstattung'));
    await tester.pumpAndSettle();
    // spending categories it can lower, no income ones
    expect(find.text('Gehalt'), findsNothing);
    expect(find.text('Lebensmittel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
