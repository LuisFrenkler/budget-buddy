import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/auto_save.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-up never counts a booking twice, even past 500 bookings', () {
    final now = DateTime(2026, 10, 27);
    final tx = [
      for (var i = 0; i < 600; i++)
        Transaction(
            id: 't$i', amountCents: 150, category: 'Lebensmittel',
            date: DateTime(2026, 1, 1).add(Duration(hours: 10 * i)), isIncome: false),
    ];
    final g = Goal(
        id: 'g', name: 'Urlaub', emoji: '🏖️', targetCents: 10000000, createdAt: DateTime(2025),
        roundUp: true, roundUpSince: DateTime(2026, 1, 1));

    expect(AutoSave.apply(g, tx, now), 600 * 50);
    expect(g.roundedIds.length, lessThan(520));
    expect(AutoSave.apply(g, tx, now), 0);
    expect(g.savedCents, 600 * 50);
  });
}
