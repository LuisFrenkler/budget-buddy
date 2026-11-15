// Buddy's short tip on Start: the one thing in the user's own numbers worth
// a look right now, with the question that leads into the chat. Null when
// nothing stands out; the card then shows its general questions.
import 'package:hive/hive.dart';
import '../models/budget.dart';
import '../models/transaction.dart';
import '../utils/merchant.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import 'category_coach.dart';
import 'contracts.dart';
import 'forecast_service.dart';
import 'goals_service.dart';
import 'sub_tips.dart';
import 'vorsorge.dart';
import 'wealth.dart';
import 'db.dart';
import '../l10n/l10n.dart';

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
        return BuddyTip(tr('Dein Budget für {x} ist um {y} überschritten.', {'x': b.category, 'y': Money.format(-left)}),
            tr('Wie bekomme ich mein Budget für {x} wieder in den Griff?', {'x': b.category}));
      }
      if (left <= b.limitCents * 0.2 && days > 3) {
        return BuddyTip(tr('Noch {x} im Budget für {y}, und noch {days} Tage.', {'x': Money.format(left), 'y': b.category, 'days': days}),
            tr('Wie komme ich mit meinem Budget für {x} bis zum Monatsende hin?', {'x': b.category}));
      }
    }
    // 2. many bookings stuck in Sonstiges, cleanup without burning KI quota
    final misc = CategoryCoach.miscCount();
    if (misc >= 5) {
      return BuddyTip(
          tr('{misc} Umsätze stecken in Sonstiges. Buddy hilft beim Einordnen.', {'misc': misc}),
          tr('Sonstiges aufräumen'));
    }
    // 3. a contract got more expensive
    final contracts = Contracts.detect(tx, now: today);
    final raised = contracts.where((c) => c.priceChange > 0).toList();
    if (raised.isNotEmpty) {
      final c = raised.first;
      return BuddyTip(tr('{x} ist teurer geworden.', {'x': c.name}),
          tr('Sollte ich {x} kündigen oder behalten?', {'x': c.name}));
    }
    // 4. known Abo with a cheaper path, running >6 months: once per calendar year
    if (Hive.isBoxOpen('settings')) {
      final box = Hive.box('settings');
      final year = today.year;
      for (final c in contracts) {
        final tip = SubTips.forName(c.name);
        if (tip == null) continue;
        if (today.difference(c.payments.first.date).inDays < 183) continue;
        final key = 'subTipYear_${Merchant.key(c.name)}';
        if (box.get(key) == year) continue;
        final gone = box.get('hintsDismissed');
        if (gone is List && gone.contains('abo-tip_$year-${Merchant.key(c.name)}')) continue;
        box.put(key, year);
        return BuddyTip(tip.text, tr('Wie spare ich bei {x}?', {'x': tip.provider}));
      }
    }
    // 5. free cash this month is running low
    final forecast = ForecastService.build(tx,
        goals: GoalsService.all(), balanceCents: balanceCents, now: today);
    if (forecast != null && forecast.freeCents >= 0 && forecast.pace == ForecastPace.tight) {
      return BuddyTip(
          tr('Noch {x} frei bis Monatsende, eher knapp.', {'x': Money.format(forecast.freeCents)}),
          tr('Wie viel ist diesen Monat noch frei?'));
    }
    // 6. many purchases at one place this month: small amounts add up
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
      return BuddyTip(tr('Du warst diesen Monat {x}× bei {y}, zusammen {z}.', {'x': s.count, 'y': s.name, 'z': Money.format(s.cents)}),
          'Wie kann ich bei ${s.name} sparen?');
    }
    // 7. emergency fund still thin
    final emergency = Wealth.emergency(tx, now: today);
    if (emergency.targetCents > 0 && emergency.progress < 0.5) {
      return BuddyTip(
          tr('Dein Notgroschen steht bei {x} % von {y}.', {'x': (emergency.progress * 100).round(), 'y': Money.format(emergency.targetCents)}),
          'Wie baue ich einen Notgroschen auf?');
    }
    // 8. vorsorge gap once configured
    if (Vorsorge.configured) {
      final r = Vorsorge.build(input: Vorsorge.load(), holdings: DB.getHoldings(), goals: GoalsService.all());
      if (!r.gapClosed && r.gapMonthlyCents > 5000) {
        return BuddyTip(
            tr('Rentenlücke grob {x} im Monat. Etwa {y} mehr sparen würde sie schließen.', {'x': Money.format(r.gapMonthlyCents), 'y': Money.format(r.saveExtraMonthlyCents)}),
            tr('Wie schließe ich meine Rentenlücke?'));
      }
    }
    // 9. several open subscriptions, gentle nudge
    if (contracts.length >= 3) {
      return BuddyTip(tr('Du hast {x} laufende Verträge, zusammen {y} im Monat.', {'x': contracts.length, 'y': Money.format(Contracts.monthlyTotal(contracts))}),
          tr('Welche Abos und Verträge habe ich?'));
    }
    return null;
  }
}
