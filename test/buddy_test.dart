import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/finance_snapshot.dart';
import 'package:budget_buddy/services/local_buddy.dart';

Transaction _t(String note, String cat, int cents, DateTime d, {bool income = false}) =>
    Transaction(id: '$note$d$cents', amountCents: cents, category: cat, date: d, isIncome: income, note: note);

void main() {
  final now = DateTime(2026, 10, 20);
  final tx = [
    for (int m = 7; m <= 10; m++) ...[
      _t('Gehalt', 'Gehalt', 300000, DateTime(2026, m, 1), income: true),
      _t('Miete', 'Wohnen', 90000, DateTime(2026, m, 3)),
      _t('Netflix', 'Unterhaltung', 1399, DateTime(2026, m, 12)),
      _t('REWE', 'Lebensmittel', m == 10 ? 60000 : 30000, DateTime(2026, m, 15)),
    ],
  ];
  final s = FinanceSnapshot.build(tx: tx, openingCents: 100000, budgets: const [], holdings: const [], now: now);

  test('snapshot sums months, balance and contracts', () {
    expect(s.current.expenses, 90000 + 1399 + 60000);
    expect(s.balanceCents, 100000 + 4 * 300000 - 3 * (90000 + 1399 + 30000) - (90000 + 1399 + 60000));
    expect(s.contracts.map((c) => c.name), containsAll(['Miete', 'Netflix']));
    expect(s.toJson()['monate'], hasLength(6));
  });

  test('saving tips point at what grew this month', () {
    final a = LocalBuddy.answer('Wo kann ich sparen?', s);
    expect(a, contains('Lebensmittel'));
    expect(a, contains('Netflix'));
  });

  test('affordability uses the average surplus', () {
    final a = LocalBuddy.answer('Kann ich mir 800 € Urlaub leisten?', s);
    // past months: 3.000 € in, 1.213,99 € out
    expect(a, contains('1.786,01'));
    expect(a, contains('1 Monat'));
  });

  test('lists contracts', () {
    expect(LocalBuddy.answer('Welche Abos habe ich?', s), contains('Miete'));
  });
}
