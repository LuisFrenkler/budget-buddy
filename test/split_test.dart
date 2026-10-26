import 'package:budget_buddy/models/split.dart';
import 'package:flutter_test/flutter_test.dart';

SplitExpense _e(String id, int cents, int paidBy, List<int> among) => SplitExpense(
    id: id, title: id, cents: cents, paidBy: paidBy, shares: SplitExpense.even(cents, among), date: DateTime(2026, 10, 1));

void main() {
  test('even split keeps every cent', () {
    expect(SplitExpense.even(1000, [0, 1, 2]), {0: 334, 1: 333, 2: 333});
    expect(SplitExpense.even(1000, [0, 1, 2]).values.reduce((a, b) => a + b), 1000);
  });

  test('balances and the fewest transfers', () {
    final g = SplitGroup(id: 'g', name: 'WG', emoji: '🏠', members: ['Ich', 'Lisa', 'Tom'], expenses: [
      _e('Einkauf', 9000, 0, [0, 1, 2]), // I paid 90, 30 each
      _e('Pizza', 3000, 1, [0, 1, 2]), // Lisa paid 30, 10 each
      _e('Kino', 2400, 2, [1, 2]), // Tom paid 24 for him and Lisa
    ]);
    // me: +90 -30 -10 = 50; Lisa: -30 +30 -10 -12 = -22; Tom: -30 -10 +24 -12 = -28
    expect(SplitMath.balances(g), [5000, -2200, -2800]);
    final t = SplitMath.settleUp(g);
    expect(t.length, 2);
    expect(t.every((x) => x.to == 0), isTrue);
    expect(t.fold<int>(0, (s, x) => s + x.cents), 5000);
  });

  test('settlements count and everything round-trips', () {
    final g = SplitGroup(id: 'g', name: 'Paar', emoji: '💑', members: ['Ich', 'Alex'], expenses: [
      _e('Urlaub', 50000, 0, [0, 1]),
    ]);
    g.settlements.add(Settlement(1, 0, 20000, DateTime(2026, 10, 5)));
    expect(SplitMath.balances(g), [5000, -5000]);
    final back = SplitGroup.fromMap(g.toMap());
    expect(SplitMath.balances(back), [5000, -5000]);
    expect(back.expenses.single.shares, {0: 25000, 1: 25000});
    g.settlements.add(Settlement(1, 0, 5000, DateTime(2026, 10, 6)));
    expect(SplitMath.settleUp(g), isEmpty);
  });

  test('who I am and the invite code stay on this device', () {
    final g = SplitGroup(id: 'g', name: 'WG', emoji: '🏠', members: ['Luis', 'Lisa'], me: 1, code: 'J57NVN', version: 3,
        expenses: [_e('Pizza', 3000, 0, [0, 1])]);
    final back = SplitGroup.fromMap(g.toMap());
    expect(back.me, 1);
    expect(back.code, 'J57NVN');
    expect(back.shared, isTrue);
    // Lisa owes Luis 15 €: from Lisa's device that is her own debt
    expect(SplitMath.balances(back)[back.me], -1500);
    // the server copy carries no device fields
    expect(g.toShared().containsKey('me'), isFalse);
    expect(g.toShared().containsKey('code'), isFalse);
  });
}
