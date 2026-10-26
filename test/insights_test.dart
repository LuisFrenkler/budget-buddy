import 'package:budget_buddy/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/services/insights_service.dart';

void main() {
  group('InsightsService', () {
    test('reports a month-over-month increase', () {
      final out = InsightsService.generate(
        thisByCat: {'Lebensmittel': 12000},
        lastByCat: {'Lebensmittel': 10000},
        thisExpenses: 12000,
        lastExpenses: 10000,
      );
      expect(out.any((s) => s.contains('20 % mehr')), isTrue);
      expect(out.first, startsWith('Du hast'));
    });

    test('reports a decrease', () {
      final out = InsightsService.generate(
        thisByCat: {'Transport': 5000},
        lastByCat: {'Transport': 10000},
        thisExpenses: 5000,
        lastExpenses: 10000,
      );
      expect(out.any((s) => s.contains('weniger')), isTrue);
    });

    test('names the biggest category', () {
      final out = InsightsService.generate(
        thisByCat: {'Wohnen': 80000, 'Essen & Trinken': 5000},
        lastByCat: {},
        thisExpenses: 85000,
        lastExpenses: 0,
      );
      expect(out.any((s) => s.contains('Größter Posten: Wohnen')), isTrue);
    });

    test('detects the category with the biggest increase', () {
      final out = InsightsService.generate(
        thisByCat: {'Essen & Trinken': 9000, 'Wohnen': 50000},
        lastByCat: {'Essen & Trinken': 3000, 'Wohnen': 50000},
        thisExpenses: 59000,
        lastExpenses: 53000,
      );
      expect(out.any((s) => s.contains('Essen & Trinken ist um')), isTrue);
    });

    test('no data yields no insights', () {
      expect(InsightsService.generate(
        thisByCat: {}, lastByCat: {}, thisExpenses: 0, lastExpenses: 0), isEmpty);
    });

    test('respects the max count', () {
      final out = InsightsService.generate(
        thisByCat: {'A': 9000, 'B': 1000},
        lastByCat: {'A': 3000, 'B': 500},
        thisExpenses: 10000, lastExpenses: 4000, max: 2);
      expect(out.length, lessThanOrEqualTo(2));
    });
  
    test('running month: same days compared, rent left out', () {
      Transaction t(String id, int c, String cat, DateTime d, {String? note}) =>
          Transaction(id: id, amountCents: c, category: cat, date: d, isIncome: false, note: note);
      final all = [
        for (var m = 7; m <= 10; m++) t('r$m', 90000, 'Wohnen', DateTime(2026, m, 1), note: 'Miete'),
        t('s1', 10000, 'Lebensmittel', DateTime(2026, 9, 5)),
        t('s2', 40000, 'Lebensmittel', DateTime(2026, 9, 25)), // after the 12th: not compared
        t('o1', 12000, 'Lebensmittel', DateTime(2026, 10, 6)),
      ];
      final out = InsightsService.forMonth(all, DateTime(2026, 10), now: DateTime(2026, 10, 12));
      expect(out.first, 'Bis heute gibst du 20 % mehr aus als im Vormonat zur gleichen Zeit.');
      expect(out.any((s) => s.contains('Wohnen')), isFalse);
      expect(out.any((s) => s.contains('Größter Posten: Lebensmittel')), isTrue);
    });
  });
}
