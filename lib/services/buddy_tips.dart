// The one next step on Start: the thing in the user's own numbers worth
// doing right now, with the question that makes the agent do it. What the
// finds above it already say is never said again. Null when nothing stands
// out; the card then shows its general questions.
import 'package:hive/hive.dart';
import '../models/budget.dart';
import '../models/transaction.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import 'ahead_agent.dart';
import 'buddy_log.dart';
import 'buddy_service.dart';
import 'category_coach.dart';
import 'contracts.dart';
import 'forecast_service.dart';
import 'goals_service.dart';
import 'hints_service.dart';
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
    // welcome already built this month's forecast; skip a second ledger scan
    MonthForecast? knownForecast,
    // today's hints when the caller has them; otherwise the ones the start lays out
    List<Hint>? hints,
  }) {
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final forecast = knownForecast ??
        ForecastService.build(tx, goals: GoalsService.all(), balanceCents: balanceCents, now: today);
    final all = hints ?? _hints(tx, budgets, forecast, today);
    final since = _visitBefore(day);
    BuddyTip? step(Set<HintKind> kinds) {
      final h = all.where((h) => kinds.contains(h.kind) && h.question != null).firstOrNull;
      return h == null ? null : BuddyTip('${h.title}.', h.question!);
    }

    // 1. money runs short and no find says so: income is late, the month will not work out
    final late = step(const {HintKind.incomeMissing});
    if (late != null) return late;
    final low = step(const {HintKind.lowMonth});
    if (low != null) {
      return forecast != null && forecast.freeCents < 0
          ? BuddyTip(tr('Bis Monatsende fehlen etwa {x}.', {'x': Money.format(-forecast.freeCents)}), low.question)
          : low;
    }
    // 2. the salary is new since the last visit: a plan from the person's own numbers
    final salary = tx
        .where((t) =>
            t.isEarning &&
            t.category == 'Gehalt' &&
            t.amountCents >= 50000 &&
            !t.date.isAfter(today) &&
            !t.date.isBefore(since ?? day.subtract(const Duration(days: 2))) &&
            day.difference(t.date).inDays <= 7)
        .firstOrNull;
    // money put aside since it came: the plan is done
    final planned = salary != null &&
        BuddyLog.all().any((e) => !e.undone && const {'save', 'goal'}.contains(e.kind) && !e.at.isBefore(salary.date));
    if (salary != null && !planned) {
      final fixed = forecast?.fixedCents ?? 0;
      final aside = (forecast?.goalsCents ?? 0) + (forecast?.reserveCents ?? 0);
      final free = salary.amountCents - fixed - aside;
      final s = Money.format(salary.amountCents);
      // without fixed costs, or with nothing left of it, there is no plan to show: only the salary
      if (fixed <= 0 || free <= 0) {
        return BuddyTip(tr('Dein Gehalt ist da: {x}.', {'x': s}),
            tr('Mein Gehalt ist da. Wie viel sollte ich davon zur Seite legen?'));
      }
      final p = {'s': s, 'f': Money.format(fixed), 'a': Money.format(aside), 'x': Money.format(free)};
      return BuddyTip(
          aside > 0
              ? tr('Gehalt da: {s}. {f} fix, {a} zurücklegen, {x} frei.', p)
              : tr('Gehalt da: {s}. {f} fix, {x} frei.', p),
          tr('Mein Gehalt von {s} ist da: {f} fix, {x} frei. Schlag mir vor, wie viel ich jetzt zurücklege und wohin.', p));
    }
    // 3. a budget that is gone or nearly gone: something to act on today
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
    // 4. planning with a date: a yearly payment is coming, a goal falls behind
    final plan = step(const {HintKind.periodicDue, HintKind.goalBehind});
    if (plan != null) return plan;
    // 5. back after some days: what happened since, in one line
    if (since != null && day.difference(since).inDays >= 3) {
      final fresh = tx.where((t) => !t.date.isBefore(since) && !t.date.isAfter(today)).toList();
      final spent = fresh.fold<int>(0, (s, t) => s + (Categories.counts(t.category) ? t.spendCents : 0));
      final paid = fresh.any((t) => t.isEarning && t.category == 'Gehalt' && t.amountCents >= 50000);
      if (spent > 0) {
        final d = day.difference(since).inDays < 7 ? Dates.weekdays[since.weekday - 1] : tr('dem {d}', {'d': Dates.dayMonth(since)});
        return BuddyTip(
            tr('Seit {d}: {x}.', {
              'd': d,
              'x': [if (paid) tr('Gehalt da'), tr('{x} ausgegeben', {'x': Money.format(spent)})].join(', '),
            }),
            tr('Was ist seit {d} mit meinem Geld passiert? Zeig mir, was auffällt.', {'d': d}));
      }
    }
    // 6. many bookings stuck in Sonstiges, cleanup without burning KI quota
    final misc = CategoryCoach.miscCount();
    if (misc >= 5) {
      return BuddyTip(
          tr('{misc} Umsätze stecken in Sonstiges. Ahead hilft beim Einordnen.', {'misc': misc}),
          tr('Sonstiges aufräumen'));
    }
    // (a price rise and a cheaper plan are finds on the start, not tips)
    final contracts = Contracts.detect(tx, now: today);
    // 7. free cash this month is running low
    if (forecast != null && forecast.freeCents >= 0 && forecast.pace == ForecastPace.tight) {
      return BuddyTip(
          tr('Noch {x} frei bis Monatsende, eher knapp.', {'x': Money.format(forecast.freeCents)}),
          tr('Wie viel ist diesen Monat noch frei?'));
    }
    // 8. many purchases at one place this month: small amounts add up
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
    // 9. emergency fund still thin
    final emergency = Wealth.emergency(tx, now: today);
    if (emergency.targetCents > 0 && emergency.progress < 0.5) {
      return BuddyTip(
          tr('Dein Notgroschen steht bei {x} % von {y}.', {'x': (emergency.progress * 100).round(), 'y': Money.format(emergency.targetCents)}),
          'Wie baue ich einen Notgroschen auf?');
    }
    // 10. vorsorge gap once configured
    if (Vorsorge.configured) {
      final r = Vorsorge.build(input: Vorsorge.load(), holdings: DB.getHoldings(), goals: GoalsService.all());
      if (!r.gapClosed && r.gapMonthlyCents > 5000) {
        return BuddyTip(
            tr('Rentenlücke grob {x} im Monat. Etwa {y} mehr sparen würde sie schließen.', {'x': Money.format(r.gapMonthlyCents), 'y': Money.format(r.saveExtraMonthlyCents)}),
            tr('Wie schließe ich meine Rentenlücke?'));
      }
    }
    // 11. several open subscriptions, gentle nudge (unless the start lays them out or they were put off)
    if (contracts.length >= 3 &&
        AheadAgent.snoozed['contracts']?.isAfter(today) != true &&
        !AheadAgent.run(tx: tx, hints: all, now: today).any((f) => f.id == 'contracts')) {
      return BuddyTip(tr('Du hast {x} laufende Verträge, zusammen {y} im Monat.', {'x': contracts.length, 'y': Money.format(Contracts.monthlyTotal(contracts))}),
          tr('Welche Abos und Verträge habe ich?'));
    }
    return null;
  }

  // the hints behind the finds on the start, from the same state the feed reads
  static List<Hint> _hints(List<Transaction> tx, List<Budget> budgets, MonthForecast? forecast, DateTime today) {
    try {
      return HintsService.current(
          tx: tx,
          budgets: budgets,
          goals: GoalsService.all(),
          freeCents: forecast?.freeCents,
          balanceCents: BuddyService.cashCents(),
          now: today);
    } catch (_) {
      return const [];
    }
  }

  // the day of the visit before today's; kept as [before, latest] and moved on once a day,
  // so the step stays the same all day
  // shortcut: "new" goes by the booking's date; a bank that books late shows up a day later
  static DateTime? _visitBefore(DateTime day) {
    if (!Hive.isBoxOpen('settings')) return null;
    final box = Hive.box('settings');
    final seen = [for (final s in (box.get('startSeen') as List?) ?? const []) DateTime.tryParse('$s')];
    final latest = seen.lastOrNull;
    if (latest == day) return seen.first;
    box.put('startSeen', ['${latest ?? ''}', '$day']);
    return latest;
  }
}
