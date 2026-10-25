// Buddy's weekly report: how the last week went against the usual, where
// the money went, and one concrete thing to try next week.
//
// A week runs Monday to Sunday. The report for a week is ready on Sunday
// at 18:00; before that the previous week is shown.
import '../models/transaction.dart';
import '../utils/money.dart';

class CategoryWeek {
  final String category;
  final int cents;
  final int usualCents; // average of the four weeks before
  final int count;
  const CategoryWeek(this.category, this.cents, this.usualCents, this.count);
}

class WeeklyReport {
  final DateTime start; // Monday
  final int spentCents;
  final int incomeCents;
  final int usualCents; // average spending of the four weeks before, 0 without history
  final List<int> perDay; // Monday .. Sunday
  final List<CategoryWeek> categories; // biggest first
  final Transaction? biggest;
  final int noSpendDays;
  final String headline;
  final String summary;
  final String tip;

  const WeeklyReport({
    required this.start,
    required this.spentCents,
    required this.incomeCents,
    required this.usualCents,
    required this.perDay,
    required this.categories,
    required this.biggest,
    required this.noSpendDays,
    required this.headline,
    required this.summary,
    required this.tip,
  });

  DateTime get end => DateTime(start.year, start.month, start.day + 6);

  // relative change against the usual week, null without history
  double? get change => usualCents <= 0 ? null : (spentCents - usualCents) / usualCents;

  // ISO 8601 week number
  int get week {
    final thursday = DateTime(start.year, start.month, start.day + 3);
    final firstThursday = DateTime(thursday.year, 1, 4);
    final firstMonday = DateTime(firstThursday.year, 1, 4 - (firstThursday.weekday - 1));
    return DateTime.utc(thursday.year, thursday.month, thursday.day)
                .difference(DateTime.utc(firstMonday.year, firstMonday.month, firstMonday.day))
                .inDays ~/
            7 +
        1;
  }

  // the day with the most spending, 0 = Monday
  int get topDay {
    var best = 0;
    for (var i = 1; i < 7; i++) {
      if (perDay[i] > perDay[best]) best = i;
    }
    return best;
  }
}

class WeeklyReportService {
  static const weekdays = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime weekStart(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  // the Monday of the week the report is about right now
  static DateTime reportWeek(DateTime now) {
    final monday = weekStart(now);
    if (now.weekday == DateTime.sunday && now.hour >= 18) return monday;
    return DateTime(monday.year, monday.month, monday.day - 7);
  }

  // the next moment a new report is ready: Sunday 18:00
  static DateTime nextReady(DateTime now) {
    final monday = weekStart(now);
    final sunday = DateTime(monday.year, monday.month, monday.day + 6, 18);
    return now.isBefore(sunday) ? sunday : DateTime(sunday.year, sunday.month, sunday.day + 7, 18);
  }

  static bool _inWeek(Transaction t, DateTime monday) {
    final d = _day(t.date);
    return !d.isBefore(monday) && d.isBefore(DateTime(monday.year, monday.month, monday.day + 7));
  }

  static WeeklyReport? build(List<Transaction> tx, {DateTime? now, DateTime? week}) {
    final monday = week ?? reportWeek(now ?? DateTime.now());
    final thisWeek = tx.where((t) => _inWeek(t, monday)).toList();
    final expenses = thisWeek.where((t) => !t.isIncome).toList();
    if (expenses.isEmpty) return null;

    final spent = expenses.fold<int>(0, (s, t) => s + t.amountCents);
    final income = thisWeek.where((t) => t.isIncome).fold<int>(0, (s, t) => s + t.amountCents);

    final perDay = List<int>.filled(7, 0);
    for (final t in expenses) {
      perDay[t.date.weekday - 1] += t.amountCents;
    }

    // the four weeks before, for "the usual"; only weeks with any bookings count
    final before = <int>[];
    final usualByCategory = <String, int>{};
    var weeksWithData = 0;
    for (var w = 1; w <= 4; w++) {
      final m = DateTime(monday.year, monday.month, monday.day - 7 * w);
      final list = tx.where((t) => !t.isIncome && _inWeek(t, m)).toList();
      if (list.isEmpty) continue;
      weeksWithData++;
      before.add(list.fold(0, (s, t) => s + t.amountCents));
      for (final t in list) {
        usualByCategory[t.category] = (usualByCategory[t.category] ?? 0) + t.amountCents;
      }
    }
    final usual = before.isEmpty ? 0 : before.reduce((a, b) => a + b) ~/ before.length;

    final byCategory = <String, List<Transaction>>{};
    for (final t in expenses) {
      byCategory.putIfAbsent(t.category, () => []).add(t);
    }
    final categories = [
      for (final e in byCategory.entries)
        CategoryWeek(
          e.key,
          e.value.fold(0, (s, t) => s + t.amountCents),
          weeksWithData == 0 ? 0 : (usualByCategory[e.key] ?? 0) ~/ weeksWithData,
          e.value.length,
        ),
    ]..sort((a, b) => b.cents.compareTo(a.cents));

    expenses.sort((a, b) => b.amountCents.compareTo(a.amountCents));
    final today = _day(now ?? DateTime.now());
    // only days that are over count as "no spend" days
    final noSpend = [
      for (var i = 0; i < 7; i++)
        if (perDay[i] == 0 && DateTime(monday.year, monday.month, monday.day + i).isBefore(today)) i
    ].length;

    final change = usual <= 0 ? null : (spent - usual) / usual;
    final headline = change == null
        ? 'Deine erste Woche im Blick'
        : change <= -0.1
            ? 'Sparsame Woche 💪'
            : change >= 0.15
                ? 'Eine teure Woche'
                : 'Eine ganz normale Woche';
    final summary = change == null
        ? 'Du hast ${Money.format(spent)} ausgegeben. Ab nächster Woche vergleiche ich mit deinem Schnitt.'
        : change.abs() < 0.03
            ? '${Money.format(spent)} ausgegeben, genau dein Schnitt.'
            : '${Money.format(spent)} ausgegeben, ${Money.format((spent - usual).abs())} '
                '${spent < usual ? 'weniger' : 'mehr'} als in einer üblichen Woche.';

    return WeeklyReport(
      start: monday,
      spentCents: spent,
      incomeCents: income,
      usualCents: usual,
      perDay: perDay,
      categories: categories,
      biggest: expenses.first,
      noSpendDays: noSpend,
      headline: headline,
      summary: summary,
      tip: _tip(categories, spent, usual),
    );
  }

  // one concrete idea for next week, from what stood out
  static String _tip(List<CategoryWeek> categories, int spent, int usual) {
    // the category that grew the most against its usual
    CategoryWeek? jump;
    for (final c in categories) {
      final diff = c.cents - c.usualCents;
      if (c.usualCents > 0 && diff >= 2000 && diff >= c.usualCents * 0.3) {
        if (jump == null || diff > jump.cents - jump.usualCents) jump = c;
      }
    }
    if (jump != null) {
      final diff = jump.cents - jump.usualCents;
      return '${jump.category} lag ${Money.format(diff)} über deinem Schnitt. '
          'Schaffst du nächste Woche wieder ${Money.format(jump.usualCents)}, '
          'sind das aufs Jahr rund ${Money.format(diff * 52 ~/ 100 * 100)} mehr für dich.';
    }
    // many small purchases add up
    for (final c in categories) {
      if (c.count >= 4 && c.cents ~/ c.count <= 1500) {
        return '${c.count} kleine Käufe bei ${c.category}, zusammen ${Money.format(c.cents)}. '
            'Halb so oft wären ${Money.format(c.cents * 26 ~/ 100 * 100)} im Jahr.';
      }
    }
    if (usual > 0 && spent < usual) {
      return 'Du lagst ${Money.format(usual - spent)} unter deinem Schnitt. '
          'Leg den Betrag gleich auf ein Sparziel, dann ist er sicher.';
    }
    return 'Setz dir für deine größte Kategorie ein Wochenlimit. '
        'Buddy sagt dir Bescheid, bevor es knapp wird.';
  }
}
