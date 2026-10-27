// Engine that turns recurring rules into actual transactions.
//
// The date math is kept as pure, testable functions; process() applies them
// against the database. It is called on app start so any occurrences that came
// due while the app was closed are backfilled.
import 'package:uuid/uuid.dart';
import '../models/recurring.dart';
import '../models/transaction.dart';
import 'db.dart';

class RecurringService {
  static const _uuid = Uuid();

  // the intervals offered in the UI
  static const intervals = ['täglich', 'wöchentlich', 'monatlich', 'jährlich'];

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // advances a date by one interval. monthly/yearly clamp the day to the
  // length of the target month (e.g. Jan 31 + 1 month -> Feb 28).
  static DateTime advance(DateTime d, String interval) {
    switch (interval) {
      case 'täglich':
        return DateTime(d.year, d.month, d.day + 1); // not +24 h: wrong across a DST change
      case 'wöchentlich':
        return DateTime(d.year, d.month, d.day + 7);
      case 'jährlich':
        return _clamp(d.year + 1, d.month, d.day);
      case 'monatlich':
      default:
        var m = d.month + 1;
        var y = d.year;
        if (m > 12) {
          m = 1;
          y++;
        }
        return _clamp(y, m, d.day);
    }
  }

  // builds a date, clamping the day to the last day of that month
  static DateTime _clamp(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > lastDay ? lastDay : day);
  }

  // the next date this rule should fire on
  static DateTime nextDate(RecurringRule rule) {
    return rule.lastRun == null
        ? _dateOnly(rule.startDate)
        : advance(_dateOnly(rule.lastRun!), rule.interval);
  }

  // all occurrence dates that are due up to and including `today`
  static List<DateTime> dueOccurrences(RecurringRule rule, DateTime today) {
    if (!rule.active) return [];
    final t = _dateOnly(today);
    var next = nextDate(rule);

    final out = <DateTime>[];
    var guard = 0;
    while (!next.isAfter(t) && guard < 2000) {
      out.add(next);
      next = advance(next, rule.interval);
      guard++;
    }
    return out;
  }

  // A paused rule switched back on carries on from today: the dates it missed
  // while paused are skipped, not booked afterwards (that is what pausing is for).
  static void skipPaused(RecurringRule rule, DateTime today) {
    final t = _dateOnly(today);
    final missed = dueOccurrences(rule, today).where((d) => d.isBefore(t)).toList();
    if (missed.isNotEmpty) rule.lastRun = missed.last;
  }

  // generates all due transactions for every rule, returning how many were made.
  // [today] defaults to now; tests and the demo data pass a fixed date.
  static Future<int> process({DateTime? today}) async {
    today ??= DateTime.now();
    int created = 0;

    for (final rule in DB.getRules()) {
      final due = dueOccurrences(rule, today);
      if (due.isEmpty) continue;

      for (final date in due) {
        await DB.addTx(Transaction(
          id: _uuid.v4(),
          amountCents: rule.amountCents,
          category: rule.category,
          date: date,
          isIncome: rule.isIncome,
          note: rule.note,
        ));
        created++;
      }

      rule.lastRun = due.last;
      await DB.updateRule(rule);
    }

    if (created > 0) await DB.checkBadges();
    return created;
  }
}
