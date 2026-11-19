// Sign-up leads with what the refund check found, the tax page asks for the
// ELSTER account before the numbers and works without an account.
import 'dart:typed_data';

import 'package:budget_buddy/screens/auth_screens.dart';
import 'package:budget_buddy/screens/tax_screen.dart';
import 'package:budget_buddy/services/account_service.dart';
import 'package:budget_buddy/services/ahead_agent.dart';
import 'package:budget_buddy/services/tax_estimate.dart';
import 'package:budget_buddy/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  final today = DateTime(2026, 11, 17);

  setUpAll(() async {
    // in memory: no file writes that would outlive the fake clock
    await Hive.openBox('settings', bytes: Uint8List(0));
  });
  setUp(() async {
    await Hive.box('settings').clear();
    AccountService.current.value = null;
  });

  // tall enough that the whole page is built
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('sign-up: generic line without a check, the calm password sentence under the button', (tester) async {
    tall(tester);
    await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
    expect(find.text('Bank und Sicherung nur für dich.'), findsOneWidget);
    expect(find.text('Ahead hat für dich gefunden'), findsNothing);
    expect(find.textContaining('Passwort = '), findsNothing);
    final note = find.textContaining('Dein Passwort verschlüsselt deine Sicherung.');
    expect(tester.getTopLeft(note).dy, greaterThan(tester.getTopLeft(find.byType(FilledButton)).dy));
  });

  testWidgets('sign-up after the refund check: the amount Ahead found', (tester) async {
    tall(tester);
    // started in September of last year: that year is open and brings money back for sure
    await Hive.box('settings').put(
        'refundCheck', {'startYear': DateTime.now().year - 1, 'startMonth': 9, 'grossMonth': 3000.0, 'km': 12.0});
    final open = AheadAgent.openCents(AheadAgent.guestFinds());
    expect(open, greaterThan(0));
    await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
    expect(find.text('Ahead hat für dich gefunden'), findsOneWidget);
    expect(find.text('mind. ${Money.format(open)}'), findsOneWidget);
    expect(find.text('Bank und Sicherung nur für dich.'), findsNothing);
  });

  testWidgets('tax page without an account: ELSTER question first, filing stays local', (tester) async {
    tall(tester);
    await Hive.box('settings').put('refundCheck', {'startYear': 2022, 'startMonth': 9, 'grossMonth': 3000.0, 'km': 12.0});
    await tester.pumpWidget(MaterialApp(home: TaxScreen(now: today, year: 2022)));
    expect(tester.takeException(), isNull);

    // the account comes before the numbers, in the steps and on the page
    expect(tester.getTopLeft(find.text('ELSTER-Konto')).dx, lessThan(tester.getTopLeft(find.text('Zahlen')).dx));
    final question = find.text('Hast du schon ein ELSTER-Konto?');
    expect(tester.getTopLeft(question).dy, lessThan(tester.getTopLeft(find.text('Brutto pro Monat')).dy));
    // 44 days left: the letter still makes it, no paper route yet
    expect(find.byKey(const Key('tax-paper')), findsNothing);

    // reading a photo needs the server: a way to the account instead of a button that fails
    expect(find.byKey(const Key('tax-certificate')), findsNothing);
    expect(find.text('Konto anlegen'), findsOneWidget);

    await tester.tap(find.text('Ich habe ein Konto'));
    await tester.pumpAndSettle();
    expect(question, findsNothing);

    await tester.tap(find.byKey(const Key('tax-filed')));
    await tester.pumpAndSettle();
    expect(TaxEstimate.filedAt(2022), isNotNull);
    expect(find.byKey(const Key('tax-assessment')), findsNothing);
    expect(find.text('Konto anlegen'), findsNWidgets(2));
  });

  testWidgets('three weeks before the deadline without an account: paper stands next to ELSTER', (tester) async {
    tall(tester);
    await Hive.box('settings').put('refundCheck', {'startYear': 2022, 'startMonth': 9, 'grossMonth': 3000.0, 'km': 12.0});
    await tester.pumpWidget(MaterialApp(home: TaxScreen(now: DateTime(2026, 12, 15), year: 2022)));
    expect(find.text('Hast du schon ein ELSTER-Konto?'), findsOneWidget);
    expect(find.text('Oder auf Papier abgeben'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tax-paper')));
    await tester.pumpAndSettle();
    expect(find.text('Hast du schon ein ELSTER-Konto?'), findsNothing);
    expect(find.textContaining('Du gibst auf Papier ab.'), findsOneWidget);
  });
}
