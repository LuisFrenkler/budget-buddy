import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/wealth.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String id, int cents, DateTime date,
        {required bool income, required String category}) =>
    Transaction(
        id: id,
        amountCents: cents,
        category: category,
        date: date,
        isIncome: income);

void main() {
  final now = DateTime(2026, 10, 15);

  test('a higher savings rate is the line, even when net worth also rose', () {
    final tx = [
      _t('a1', 100000, DateTime(2026, 8, 1), income: true, category: 'Gehalt'),
      _t('a2', 80000, DateTime(2026, 8, 15),
          income: false, category: 'Lebensmittel'),
      _t('b1', 100000, DateTime(2026, 9, 1), income: true, category: 'Gehalt'),
      _t('b2', 40000, DateTime(2026, 9, 15),
          income: false, category: 'Lebensmittel'),
    ];
    expect(
      Wealth.moment(
          tx: tx, now: now),
      'Sparquote letzten Monat: 60 %, höher als im Monat davor',
    );
  });

  test('no line when the savings rate did not rise', () {
    expect(Wealth.moment(tx: const [], now: now), isNull);
  });
}
