import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/models/budget.dart';

void main() {
  group('Transaction', () {
    test('round-trips through toMap/fromMap in cents', () {
      final tx = Transaction(
        id: 'a',
        amountCents: 1299,
        category: 'Lebensmittel',
        date: DateTime(2025, 3, 5),
        isIncome: false,
      );
      final back = Transaction.fromMap(tx.toMap());
      expect(back.amountCents, 1299);
      expect(back.category, 'Lebensmittel');
      expect(back.isIncome, isFalse);
    });

    test('migrates legacy double-euro data to cents', () {
      final legacy = {
        'id': 'b',
        'amount': 12.99, // old format
        'category': 'Gehalt',
        'date': DateTime(2025, 1, 5).millisecondsSinceEpoch,
        'isIncome': true,
        'note': null,
      };
      final tx = Transaction.fromMap(legacy);
      expect(tx.amountCents, 1299);
    });

    test('amountText shows sign and German format', () {
      final income = Transaction(
          id: 'c', amountCents: 285000, category: 'Gehalt',
          date: DateTime(2025, 1, 5), isIncome: true);
      expect(income.amountText.startsWith('+'), isTrue);
      expect(income.amountText.contains('2.850,00'), isTrue);
    });
  });

  group('Budget', () {
    Budget make(int limit, int spent) {
      final b = Budget(
        category: 'Lebensmittel',
        limitCents: limit,
        startDate: DateTime(2025, 3, 1),
        endDate: DateTime(2025, 3, 31),
      );
      b.spentCents = spent;
      return b;
    }

    test('progress is a clamped fraction', () {
      expect(make(20000, 10000).progress, 0.5);
      expect(make(20000, 25000).progress, 1.0); // clamped
      expect(make(0, 100).progress, 0.0); // no divide by zero
    });

    test('isOver and remaining', () {
      expect(make(20000, 25000).isOver, isTrue);
      expect(make(20000, 25000).remainingCents, -5000);
      expect(make(20000, 5000).isOver, isFalse);
      expect(make(20000, 5000).remainingCents, 15000);
    });

    test('percent used passes 100 and survives a budget without limit', () {
      expect(make(20000, 25000).percentUsed, 125);
      expect(make(0, 100).percentUsed, 0); // used to crash the start screen
    });

    test('covers its month, and the date range reads German', () {
      expect(make(1, 0).covers(DateTime(2025, 3, 31, 23)), isTrue);
      expect(make(1, 0).covers(DateTime(2025, 4, 1)), isFalse);
      expect(make(1, 0).dateRange, '1.–31. März 2025');
    });

    test('migrates legacy double-euro limit to cents', () {
      final legacy = {
        'category': 'Wohnen',
        'limit': 200.0, // old format
        'startDate': DateTime(2025, 3, 1).millisecondsSinceEpoch,
        'endDate': DateTime(2025, 3, 31).millisecondsSinceEpoch,
      };
      expect(Budget.fromMap(legacy).limitCents, 20000);
    });
  });
}
