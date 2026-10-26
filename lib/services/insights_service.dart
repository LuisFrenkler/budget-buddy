// Generates short, human-readable German insights by comparing the current
// month's spending to the previous month. Pure and testable: it works on
// already-aggregated category maps and totals (all in cents).
import '../models/transaction.dart';
import '../utils/money.dart';
import 'contracts.dart';

class InsightsService {
  // Insights for a month from the bookings: fixed costs (rent, subscriptions)
  // are left out, they say nothing new; and a running month is compared with
  // the month before up to the same day, so the 12th is not set against a
  // complete month.
  static List<String> forMonth(List<Transaction> all, DateTime month, {DateTime? now, int max = 3}) {
    final today = now ?? DateTime.now();
    final fixed = {for (final c in Contracts.detect(all, now: today)) for (final p in c.payments) p.id};
    final running = month.year == today.year && month.month == today.month;
    final cutDay = running ? today.day : 31;
    Map<String, int> byCat(DateTime m) {
      final out = <String, int>{};
      for (final t in all) {
        if (t.isIncome || fixed.contains(t.id)) continue;
        if (t.date.year != m.year || t.date.month != m.month || t.date.day > cutDay) continue;
        out[t.category] = (out[t.category] ?? 0) + t.amountCents;
      }
      return out;
    }

    final thisByCat = byCat(month);
    final lastByCat = byCat(DateTime(month.year, month.month - 1));
    int sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);
    return generate(
      thisByCat: thisByCat,
      lastByCat: lastByCat,
      thisExpenses: sum(thisByCat),
      lastExpenses: sum(lastByCat),
      soFar: running,
      max: max,
    );
  }

  static List<String> generate({
    required Map<String, int> thisByCat,
    required Map<String, int> lastByCat,
    required int thisExpenses,
    required int lastExpenses,
    bool soFar = false, // a running month, compared up to the same day
    int max = 3,
  }) {
    final out = <String>[];

    // overall month-over-month change
    if (lastExpenses > 0 && thisExpenses > 0) {
      final pct = (thisExpenses - lastExpenses) / lastExpenses * 100;
      if (pct.abs() >= 5) {
        final dir = pct > 0 ? 'mehr' : 'weniger';
        out.add(soFar
            ? 'Bis heute gibst du ${pct.abs().toStringAsFixed(0)} % $dir aus als im Vormonat zur gleichen Zeit.'
            : 'Du hast ${pct.abs().toStringAsFixed(0)} % $dir ausgegeben als im Vormonat.');
      } else {
        out.add('Deine Ausgaben sind etwa so hoch wie im Vormonat.');
      }
    }

    // biggest spending category this month
    if (thisByCat.isNotEmpty) {
      final top = thisByCat.entries.reduce((a, b) => a.value >= b.value ? a : b);
      out.add('Größter Posten: ${top.key} (${Money.format(top.value)}).');
    }

    // category with the biggest absolute increase vs last month
    String? incCat;
    int incDelta = 0;
    thisByCat.forEach((cat, value) {
      final delta = value - (lastByCat[cat] ?? 0);
      if (delta > incDelta) {
        incDelta = delta;
        incCat = cat;
      }
    });
    if (incCat != null && incDelta > 0 && (lastByCat[incCat] ?? 0) > 0) {
      out.add('$incCat ist um ${Money.format(incDelta)} gestiegen.');
    }

    return out.take(max).toList();
  }
}
