// Buddy's short tip on Start: the one thing in the user's own numbers worth
// a look right now, with the question that leads into the chat. Null when
// nothing stands out; the card then shows its general questions.
import '../models/budget.dart';
import '../models/transaction.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import 'contracts.dart';
import 'forecast_service.dart';
import 'goals_service.dart';
import 'vorsorge.dart';
import 'wealth.dart';
import 'db.dart';

class BuddyTip {
  final String text;
  final String question;
  const BuddyTip(this.text, this.question);
}

class BuddyTips {
  static BuddyTip? pick({
    required List<Transaction> tx,
    required List<Budget> budgets,
    DateTime? now,
    int? balanceCents,
  }) {
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
    // 2. a contract got more expensive
    final contracts = Contracts.detect(tx, now: today);
    final raised = contracts.where((c) => c.priceChange > 0).toList();
    if (raised.isNotEmpty) {
      final c = raised.first;
      return BuddyTip('${c.name} ist teurer geworden.',
          'Sollte ich ${c.name} kündigen oder behalten?');
    }
    // 3. free cash this month is running low
    final forecast = ForecastService.build(tx,
        goals: GoalsService.all(), balanceCents: balanceCents, now: today);
    if (forecast != null && forecast.freeCents >= 0 && forecast.pace == ForecastPace.tight) {
      return BuddyTip(
          'Noch ${Money.format(forecast.freeCents)} frei bis Monatsende — eher knapp.',
          'Wie viel ist diesen Monat noch frei?');
    }
    // 4. many purchases at one place this month: small amounts add up
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
    // 5. emergency fund still thin
    final emergency = Wealth.emergency(tx, now: today);
    if (emergency.targetCents > 0 && emergency.progress < 0.5) {
      return BuddyTip(
          'Dein Notgroschen steht bei ${(emergency.progress * 100).round()} % — Ziel ${Money.format(emergency.targetCents)}.',
          'Wie baue ich einen Notgroschen auf?');
    }
    // 6. vorsorge gap once configured
    if (Vorsorge.configured) {
      final r = Vorsorge.build(input: Vorsorge.load(), holdings: DB.getHoldings(), goals: GoalsService.all());
      if (!r.gapClosed && r.gapMonthlyCents > 5000) {
        return BuddyTip(
            'Rentenlücke grob ${Money.format(r.gapMonthlyCents)} im Monat — ca. ${Money.format(r.saveExtraMonthlyCents)} extra sparen.',
            'Wie schließe ich meine Rentenlücke?');
      }
    }
    // 7. several open subscriptions — gentle nudge
    if (contracts.length >= 3) {
      return BuddyTip('Du hast ${contracts.length} laufende Verträge — ${Money.format(Contracts.monthlyTotal(contracts))} im Monat.',
          'Welche Abos und Verträge habe ich?');
    }
    return null;
  }
}
