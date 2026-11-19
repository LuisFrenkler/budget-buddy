// "Wo stehe ich?": the figures come from the person's own bookings, and
// without bookings the block says what is missing instead of showing zeros.
import 'dart:io';

import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/widgets/finance_stand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  final today = DateTime(2026, 11, 17);
  Transaction out(String id, int cents, String cat, int month, String note) =>
      Transaction(id: id, amountCents: cents, category: cat, isIncome: false, date: DateTime(2026, month, 3), note: note);
  final tx = [
    for (final m in [8, 9, 10, 11]) ...[out('r$m', 78000, 'Wohnen', m, 'Miete'), out('n$m', 1399, 'Unterhaltung', m, 'Netflix')],
  ];

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('stand').path);
    await Hive.openBox('settings');
  });

  test('fixed costs are every monthly contract, rent included; wealth is account plus portfolio', () {
    final f = FinanceStand.figures(tx, now: today);
    expect(f.fixedCents, 78000 + 1399);
    expect(f.contracts, 2);
    // nothing known about the account and no portfolio: no wealth to show
    expect(f.wealthCents, isNull);
    // the portfolio counts: someone with a depot does not stand at "nothing"
    expect(FinanceStand.figures(tx, depotCents: 1778000, now: today).wealthCents, 1778000);
    expect(FinanceStand.figures(tx, cashCents: 50000, depotCents: 1778000, now: today).wealthCents, 1828000);
  });

  testWidgets('without bookings it asks for them instead of showing zeros', (tester) async {
    var added = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FinanceStand(tx: const [], onAdd: () => added = true))));
    expect(find.byKey(const Key('stand-empty')), findsOneWidget);
    expect(find.byKey(const Key('stand-fixed')), findsNothing);
    await tester.tap(find.byKey(const Key('stand-add')));
    expect(added, isTrue);
  });

  testWidgets('with bookings it shows the three figures', (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: FinanceStand(tx: tx, free: '412,00 €', perDay: '31,00 €', now: today))));
    expect(find.text('412,00 €'), findsOneWidget);
    expect(find.byKey(const Key('stand-fixed')), findsOneWidget);
    expect(find.byKey(const Key('stand-wealth')), findsOneWidget);
  });
}
