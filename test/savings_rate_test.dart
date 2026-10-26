import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/savings_rate.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(int c, DateTime d, {bool income = false}) =>
    Transaction(id: '$c$d$income', amountCents: c, category: 'X', date: d, isIncome: income);

void main() {
  test('three complete months for the headline, the running month apart', () {
    final tx = [
      for (var m = 7; m <= 9; m++) ...[_t(300000, DateTime(2026, m, 1), income: true), _t(150000, DateTime(2026, m, 15))],
      _t(300000, DateTime(2026, 10, 1), income: true), // october: only salary so far
      _t(999999, DateTime(2026, 6, 10)), // june: outside the window
    ];
    final now = DateTime(2026, 10, 26);
    expect(SavingsRate.headline(tx, now: now), 50);
    final months = SavingsRate.months(tx, now: now);
    expect(months.first.running, isTrue);
    expect(months.first.rate, 100); // why the running month is shown apart
    expect(months.map((m) => m.month.month), [10, 9, 8, 7]);
  });

  test('no income, no rate; overspending is negative', () {
    expect(SavingsRate.headline([_t(5000, DateTime(2026, 9, 3))], now: DateTime(2026, 10, 2)), isNull);
    final tx = [_t(100000, DateTime(2026, 9, 1), income: true), _t(120000, DateTime(2026, 9, 9))];
    expect(SavingsRate.headline(tx, now: DateTime(2026, 10, 2)), -20);
  });
}
