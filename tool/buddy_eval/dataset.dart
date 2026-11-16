// The person the test catalog asks about: Lea, 24, first job in Hamburg.
// Six months of bookings ending today, built from fixed rules so every run
// sees the same money (only the dates move with today).
import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/finance_snapshot.dart';

class EvalData {
  static List<Transaction> bookings(DateTime today) {
    final tx = <Transaction>[];
    var n = 0;
    void add(DateTime d, double eur, String cat, String note, {bool income = false}) {
      if (d.isAfter(today)) return;
      tx.add(Transaction(
          id: 'e${n++}', amountCents: (eur * 100).round(), category: cat, date: d, isIncome: income, note: note));
    }

    for (var i = 5; i >= 0; i--) {
      final m = DateTime(today.year, today.month - i);
      DateTime day(int d) => DateTime(m.year, m.month, d);
      // income: salary on the 28th, a little side job sometimes
      add(day(28), 2350, 'Gehalt', 'Hapag-Lloyd Gehalt', income: true);
      if (i.isEven) add(day(15), 180, 'Nebenjob', 'Nachhilfe', income: true);
      // fixed costs
      add(day(1), 780, 'Wohnen', 'Miete Hufnerstraße');
      add(day(2), 58, 'Transport', 'Deutschlandticket');
      add(day(3), 29.90, 'Sport', 'FitX Fitnessstudio');
      // Netflix got more expensive this month
      add(day(5), i == 0 ? 17.99 : 13.99, 'Abos', 'Netflix');
      add(day(5), 10.99, 'Abos', 'Spotify');
      add(day(7), 15, 'Handy', 'Congstar');
      add(day(10), 42, 'Versicherung', 'Haftpflicht und Hausrat');
      // a standing transfer to savings is not spending
      add(day(29), 200, 'Umbuchung', 'Sparen Tagesgeld');
      // groceries every week
      for (final d in [4, 11, 18, 25]) {
        add(day(d), 38.40 + (d % 7) * 3.1, 'Lebensmittel', d < 15 ? 'Rewe' : 'Lidl');
      }
      add(day(21), 23.80, 'Lebensmittel', 'Edeka');
      // eating out and delivery
      add(day(9), 24.90, 'Essen gehen', 'Lieferando');
      add(day(16), 31.50, 'Essen gehen', 'Lieferando');
      add(day(23), 18.60, 'Essen gehen', 'Burger Bar');
      // shopping and fun
      add(day(12), i == 1 ? 129.99 : 49.95, 'Shopping', 'Zalando');
      add(day(19), 27.40, 'Shopping', 'Amazon');
      add(day(20), 36.00, 'Freizeit', 'Kino und Bar');
    }
    // a refund and one big purchase this year
    add(DateTime(today.year, today.month, 6), 49.95, 'Shopping', 'Zalando Rücksendung', income: true);
    add(DateTime(today.year, today.month - 3, 14), 649, 'Technik', 'MediaMarkt Laptop');
    return tx;
  }

  static List<Goal> goals(DateTime today) => [
        Goal(
          id: 'g1',
          name: 'Urlaub Portugal',
          targetCents: 120000,
          savedCents: 35000,
          deadline: DateTime(today.year + 1, 7, 1),
          emoji: '✈️',
          createdAt: DateTime(today.year, today.month - 4),
          monthlyCents: 10000,
        ),
        Goal(
            id: 'g2',
            name: 'Notgroschen',
            targetCents: 450000,
            savedCents: 180000,
            emoji: '🛟',
            createdAt: DateTime(today.year, today.month - 5)),
      ];

  static BuddyTools tools(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tx = bookings(today);
    final snapshot = FinanceSnapshot.build(
      tx: tx,
      openingCents: 120000,
      budgets: const [],
      holdings: const [],
      now: today,
      goals: goals(today),
      emergencyTargetCents: 450000,
      emergencyHaveCents: 180000,
    );
    return BuddyTools(tx: tx, snapshot: snapshot.toJson(), now: now);
  }
}
