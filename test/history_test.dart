import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/history.dart';

Transaction _tx(int cents, bool income, DateTime date) =>
    Transaction(id: '$date$cents', amountCents: cents, category: 'Test', date: date, isIncome: income);

void main() {
  group('History.dailyBalance', () {
    final tx = [
      _tx(100000, true, DateTime(2026, 1, 1, 9)),
      _tx(2000, false, DateTime(2026, 1, 3, 18)),
      _tx(500, false, DateTime(2026, 1, 3, 20)),
      _tx(30000, true, DateTime(2026, 1, 5)),
    ];

    test('one point per day with the running balance', () {
      final pts = History.dailyBalance(tx, from: DateTime(2026, 1, 1), to: DateTime(2026, 1, 5));
      expect(pts.map((p) => p.cents).toList(), [100000, 100000, 97500, 97500, 127500]);
      expect(pts.first.date, DateTime(2026, 1, 1));
      expect(pts.last.date, DateTime(2026, 1, 5));
    });

    test('transactions before the range form the starting balance', () {
      final pts = History.dailyBalance(tx, from: DateTime(2026, 1, 4), to: DateTime(2026, 1, 5));
      expect(pts.map((p) => p.cents).toList(), [97500, 127500]);
    });

    test('empty range returns no points', () {
      expect(History.dailyBalance(tx, from: DateTime(2026, 2, 1), to: DateTime(2026, 1, 1)), isEmpty);
    });

    test('firstDay finds the earliest calendar day', () {
      expect(History.firstDay(tx), DateTime(2026, 1, 1));
      expect(History.firstDay([]), isNull);
    });
  });
}
