// The find "n Verträge kosten dich x im Jahr" and the answer after the tap
// must be about the same contracts and the same sum: without the rent.
import 'dart:io';

import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/ahead_agent.dart';
import 'package:budget_buddy/services/finance_snapshot.dart';
import 'package:budget_buddy/services/local_buddy.dart';
import 'package:budget_buddy/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  final today = DateTime(2026, 11, 17);
  Transaction out(String id, int cents, String cat, int month, String note) =>
      Transaction(id: id, amountCents: cents, category: cat, isIncome: false, date: DateTime(2026, month, 3), note: note);
  final tx = [
    for (final m in [8, 9, 10, 11]) ...[
      out('r$m', 78000, 'Wohnen', m, 'Miete'),
      out('n$m', 1399, 'Unterhaltung', m, 'Netflix'),
      out('s$m', 999, 'Unterhaltung', m, 'Spotify'),
    ],
  ];

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('contracts_talk').path);
    await Hive.openBox('settings');
  });

  test('the card, its question and the offline answer name the same yearly sum, the rent apart', () {
    final find = AheadAgent.run(tx: tx, now: today).firstWhere((f) => f.id == 'contracts');
    final sum = Money.format((1399 + 999) * 12);
    expect(find.title, contains(sum));
    expect(find.title, startsWith('2 '));
    expect(find.question, contains(sum));

    final s = FinanceSnapshot.build(tx: tx, openingCents: 0, budgets: const [], holdings: const [], now: today);
    final answer = LocalBuddy.answer(find.question!, s);
    expect(answer, contains(sum));
    expect(answer, contains('Netflix'));
    expect(answer, contains('Spotify'));
    // the rent is named, but outside the sum
    expect(answer, contains('Miete'));
    expect(answer, isNot(contains(Money.format((78000 + 1399 + 999) * 12))));
  });
}
