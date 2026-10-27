// Buddy's short tip on Start: the one thing in the user's own numbers worth
// a look right now, with the question that leads into the chat. Null when
// nothing stands out; the card then shows its general questions.
import '../models/budget.dart';
import '../models/transaction.dart';
import '../utils/money.dart';
import '../utils/theme.dart';

class BuddyTip {
  final String text;
  final String question;
  const BuddyTip(this.text, this.question);
}

class BuddyTips {
  static BuddyTip? pick({required List<Transaction> tx, required List<Budget> budgets, DateTime? now}) {
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    // 1. a budget that is gone or nearly gone: something to act on today
    for (final b in budgets) {
      if (day.isBefore(b.startDate) || day.isAfter(b.endDate) || b.limitCents <= 0) continue;
      final left = b.limitCents - b.spentCents;
      final days = b.endDate.difference(day).inDays + 1;
      if (left < 0) {
        return BuddyTip('Dein Budget für ${b.category} ist um ${Money.format(-left)} überschritten.',
            'Wie bekomme ich mein Budget für ${b.category} wieder in den Griff?');
      }
      if (left <= b.limitCents * 0.2 && days > 3) {
        return BuddyTip('Noch ${Money.format(left)} im Budget für ${b.category}, und noch $days Tage.',
            'Wie komme ich mit meinem Budget für ${b.category} bis zum Monatsende hin?');
      }
    }
    // 2. many purchases at one place this month: small amounts add up
    final shops = <String, ({String name, int count, int cents})>{};
    for (final t in tx) {
      final name = t.note?.trim() ?? '';
      if (!t.isSpending || t.isIncome || name.isEmpty || !Categories.counts(t.category)) continue;
      if (t.date.year != today.year || t.date.month != today.month) continue;
      final s = shops[name.toLowerCase()];
      shops[name.toLowerCase()] = (name: name, count: (s?.count ?? 0) + 1, cents: (s?.cents ?? 0) + t.amountCents);
    }
    final frequent = shops.values.where((s) => s.count >= 4).toList()..sort((a, b) => b.cents.compareTo(a.cents));
    if (frequent.isNotEmpty) {
      final s = frequent.first;
      return BuddyTip('Du warst diesen Monat ${s.count}× bei ${s.name}, zusammen ${Money.format(s.cents)}.',
          'Wie kann ich bei ${s.name} sparen?');
    }
    return null;
  }
}
