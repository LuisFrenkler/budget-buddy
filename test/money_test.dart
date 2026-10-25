import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/utils/money.dart';

void main() {
  group('Money.parseToCents', () {
    test('parses German comma decimals', () {
      expect(Money.parseToCents('12,99'), 1299);
      expect(Money.parseToCents('5,5'), 550);
      expect(Money.parseToCents('0,01'), 1);
    });

    test('parses English dot decimals (CSV format)', () {
      expect(Money.parseToCents('12.99'), 1299);
      expect(Money.parseToCents('2850.00'), 285000);
      expect(Money.parseToCents('-67.43'), -6743);
    });

    test('handles thousands separators in both styles', () {
      expect(Money.parseToCents('1.234,56'), 123456); // German
      expect(Money.parseToCents('1,234.56'), 123456); // English
    });

    test('parses whole numbers', () {
      expect(Money.parseToCents('5'), 500);
      expect(Money.parseToCents('200'), 20000);
    });

    test('strips currency symbol and spaces', () {
      expect(Money.parseToCents('€ 12,99'), 1299);
      expect(Money.parseToCents('12,99 €'), 1299);
    });

    test('returns null for invalid input', () {
      expect(Money.parseToCents(''), isNull);
      expect(Money.parseToCents('abc'), isNull);
      expect(Money.parseToCents('  '), isNull);
    });

    test('no floating point drift on repeated addition', () {
      // the classic 0.1 + 0.2 problem stays exact with cents
      var total = 0;
      for (var i = 0; i < 3; i++) {
        total += Money.parseToCents('0,10')!;
      }
      expect(total, 30); // exactly 0,30 € — never 0.30000000000000004
    });
  });

  group('Money formatting', () {
    test('format uses German decimal comma and euro symbol', () {
      final s = Money.format(123450);
      expect(s.contains('1.234,50'), isTrue);
      expect(s.contains('€'), isTrue);
    });

    test('format handles zero', () {
      expect(Money.format(0).contains('0,00'), isTrue);
    });

    test('signed prefixes a plus for positive balances', () {
      expect(Money.signed(500).startsWith('+'), isTrue);
      expect(Money.signed(-500).startsWith('-'), isTrue);
      expect(Money.signed(0).startsWith('+'), isTrue);
    });

    test('withSign uses income/expense sign', () {
      expect(Money.withSign(1299, true).startsWith('+'), isTrue);
      expect(Money.withSign(1299, false).startsWith('-'), isTrue);
    });

    test('percent uses a German decimal comma', () {
      expect(Money.percent(35.236, digits: 2), '+35,24 %');
      expect(Money.percent(-4.25), '-4,3 %');
      expect(Money.percent(12.5, signed: false), '12,5 %');
    });
  });
}
