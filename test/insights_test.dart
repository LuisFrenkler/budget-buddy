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
  });
}
