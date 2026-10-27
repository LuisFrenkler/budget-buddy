import 'dart:io';
import 'package:budget_buddy/models/money_account.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/screens/account_screen.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/money_accounts.dart';
import 'package:budget_buddy/services/settings_service.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
    Hive.init(Directory.systemTemp.createTempSync('bb_accounts_screen').path);
    for (final name in ['transactions', 'settings', 'recurring', 'badges', 'budgets', 'holdings', 'goals', 'splits']) {
      await Hive.openBox(name);
    }
    // real disk writes belong outside the widget test's fake clock
    await Settings.setOpeningBalanceCents(100000);
    await MoneyAccounts.save(const MoneyAccount(id: 'tg', name: 'Tagesgeld', kind: 'spar', openingCents: 500000));
    await DB.addTx(Transaction(
        id: 'a', amountCents: 2000, category: 'Lebensmittel', date: DateTime.now(), isIncome: false, note: 'REWE'));
    await DB.addTx(Transaction(
        id: 'b', amountCents: 1250, category: 'Zinsen', date: DateTime.now(), isIncome: true, note: 'Zinsen', accountId: 'tg'));
  });

  testWidgets('Konto shows every account and one at a time', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final segment = ValueNotifier(0);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme(true),
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: AccountScreen(segment: segment)),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    // all accounts together
    expect(find.text('Alle'), findsOneWidget);
    expect(find.textContaining('Girokonto · 980,00'), findsOneWidget);
    expect(find.textContaining('Tagesgeld · 5.012,50'), findsOneWidget);
    expect(find.textContaining('· Tagesgeld'), findsOneWidget); // the list says where a booking was

    // one account: its own balance and bookings
    await tester.tap(find.textContaining('Tagesgeld · '));
    await tester.pump(const Duration(milliseconds: 500));
    expect(AccountScreen.selected.value, 'tg');
    expect(find.text('REWE'), findsNothing);
    expect(find.text('Zinsen'), findsWidgets);

    // a further account is one tap away
    // the add chip sits after the accounts: swipe the row to it
    await tester.drag(find.text('Alle'), const Offset(-500, 0));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byIcon(Icons.add_rounded));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100)); // the sheet slides in over a few frames
    }
    // a real bank or depot comes first, by hand second
    expect(find.text('Bankkonto verbinden'), findsOneWidget);
    expect(find.text('Depot verbinden'), findsOneWidget);
    await tester.tap(find.text('Konto von Hand'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Konto hinzufügen'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
