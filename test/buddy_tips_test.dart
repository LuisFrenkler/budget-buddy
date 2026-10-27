import 'package:budget_buddy/models/budget.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_tips.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _buy(String id, String shop, int cents, int day) => Transaction(
    id: id, amountCents: cents, category: 'Essen & Trinken', date: DateTime(2026, 10, day), isIncome: false, note: shop);

void main() {
  final now = DateTime(2026, 10, 20);

  test('many purchases at one shop become a tip', () {
    final tx = [for (var i = 0; i < 6; i++) _buy('l$i', 'Lieferando', 1570, 2 + i), _buy('r', 'REWE', 4000, 3)];
    final tip = BuddyTips.pick(tx: tx, budgets: const [], now: now)!;
    expect(tip.text, contains('6× bei Lieferando'));
    expect(tip.question, 'Wie kann ich bei Lieferando sparen?');
  });

  test('a budget running out comes first', () {
    final b = Budget(
        category: 'Essen & Trinken', limitCents: 30000, startDate: DateTime(2026, 10, 1), endDate: DateTime(2026, 10, 31))
      ..spentCents = 27700;
    final tip = BuddyTips.pick(tx: [for (var i = 0; i < 6; i++) _buy('l$i', 'Lieferando', 1570, 2 + i)], budgets: [b], now: now)!;
    expect(tip.text, contains('12 Tage'));
    expect(tip.question, contains('Budget für Essen & Trinken'));
  });

  test('nothing standing out gives no tip', () {
    expect(BuddyTips.pick(tx: [_buy('a', 'REWE', 4000, 3)], budgets: const [], now: now), isNull);
  });
}
