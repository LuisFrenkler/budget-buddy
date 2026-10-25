// Generates short, human-readable German insights by comparing the current
// month's spending to the previous month. Pure and testable: it works on
// already-aggregated category maps and totals (all in cents).
import '../utils/money.dart';

class InsightsService {
  static List<String> generate({
    required Map<String, int> thisByCat,
    required Map<String, int> lastByCat,
    required int thisExpenses,
    required int lastExpenses,
    int max = 3,
  }) {
    final out = <String>[];

    // overall month-over-month change
    if (lastExpenses > 0 && thisExpenses > 0) {
      final pct = (thisExpenses - lastExpenses) / lastExpenses * 100;
      if (pct.abs() >= 5) {
        final dir = pct > 0 ? 'mehr' : 'weniger';
        out.add('Du gibst diesen Monat ${pct.abs().toStringAsFixed(0)} % $dir aus als im Vormonat.');
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
