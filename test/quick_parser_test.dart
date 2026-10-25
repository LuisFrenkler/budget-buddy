import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/services/quick_parser.dart';

void main() {
  // a Sunday
  final now = DateTime(2026, 10, 25, 15);

  test('reads amount, category, note and "gestern"', () {
    final p = QuickParser.parse('Döner 8,50 gestern', now: now)!;
    expect(p.cents, 850);
    expect(p.isIncome, isFalse);
    expect(p.category, 'Essen & Trinken');
    expect(p.note, 'Döner');
    expect(p.date, DateTime(2026, 10, 24, 12));
  });

  test('understands merchants, euro signs and dots as decimals', () {
    final p = QuickParser.parse('REWE 23.40€', now: now)!;
    expect(p.cents, 2340);
    expect(p.category, 'Lebensmittel');
    expect(p.note, 'REWE');
  });

  test('a date is not taken for the amount', () {
    final p = QuickParser.parse('Gehalt 2.850 am 1.10.', now: now)!;
    expect(p.cents, 285000);
    expect(p.isIncome, isTrue);
    expect(p.category, 'Gehalt');
    expect(p.date, DateTime(2026, 10, 1, 12));
  });

  test('weekday means the most recent one', () {
    final p = QuickParser.parse('Kino 12 freitag', now: now)!;
    expect(p.date, DateTime(2026, 10, 23, 12));
    expect(p.category, 'Unterhaltung');
  });

  test('income from words or a plus sign', () {
    expect(QuickParser.parse('Nachhilfe 40', now: now)!.category, 'Nebenjob');
    expect(QuickParser.parse('+25 von Oma', now: now)!.isIncome, isTrue);
  });

  test('no amount, no booking', () {
    expect(QuickParser.parse('Döner gestern', now: now), isNull);
    expect(QuickParser.parse('', now: now), isNull);
  });
}
