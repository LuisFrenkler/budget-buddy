// Savings goals in the 'goals' Hive box, plus Buddy's plan for each: how
// much per month it takes, and whether the usual monthly surplus covers it.
import 'package:hive/hive.dart';
import '../models/goal.dart';
import '../utils/money.dart';
import '../l10n/l10n.dart';

class GoalPlan {
  final String text;
  final bool onTrack;
  const GoalPlan(this.text, this.onTrack);
}

class GoalsService {
  static Box get _box => Hive.box('goals');

  static List<Goal> all() {
    final list = <Goal>[];
    if (!Hive.isBoxOpen('goals')) return list;
    for (final v in _box.values) {
      try {
        list.add(Goal.fromMap(Map<String, dynamic>.from(v)));
      } catch (_) {}
    }
    // open goals first, nearest deadline first
    list.sort((a, b) {
      if (a.reached != b.reached) return a.reached ? 1 : -1;
      return (a.deadline ?? DateTime(9999)).compareTo(b.deadline ?? DateTime(9999));
    });
    return list;
  }

  static Future<void> save(Goal g) => _box.put(g.id, g.toMap());
  static Future<void> delete(String id) => _box.delete(id);

  // Buddy's plan, from the goal and the average monthly surplus
  static GoalPlan plan(Goal g, {required int avgSurplusCents, DateTime? now}) {
    final today = now ?? DateTime.now();
    if (g.reached) return GoalPlan(tr('Ziel erreicht.'), true);
    final deadline = g.deadline;
    // the date has passed: say so instead of pretending a month is left
    if (deadline != null && deadline.isBefore(DateTime(today.year, today.month, today.day))) {
      return GoalPlan(
          tr('Datum vorbei, noch {x}. Neues Datum setzen.', {'x': Money.format(g.remainingCents)}),
          false);
    }
    // on autopilot: the plan is what the user set up, measured against the date
    if (g.monthlyCents > 0) {
      final months = (g.remainingCents / g.monthlyCents).ceil();
      final need = g.monthlyNeeded(today);
      if (need != null && g.monthlyCents < need) {
        return GoalPlan(
            tr('{x}/Monat ist knapp, bis zum Datum bräuchtest du {y}.', {'x': Money.format(g.monthlyCents), 'y': Money.format(need)}),
            false);
      }
      return GoalPlan(
          tr('{x} im Monat, fertig in {months} {y}.', {'x': Money.format(g.monthlyCents), 'months': months, 'y': months == 1 ? tr('Monat') : tr('Monaten')}),
          true);
    }
    final need = g.monthlyNeeded(today);
    if (need == null) {
      if (avgSurplusCents <= 0) {
        return GoalPlan(tr('Mit Datum rechne ich dir einen Monatsplan aus.'), false);
      }
      // without a date: how long at half of the usual surplus
      // rounded down to full 10 €, a number people actually set up
      final perMonth = (avgSurplusCents ~/ 2 ~/ 1000) * 1000;
      if (perMonth <= 0) {
        return GoalPlan(tr('Mit Datum rechne ich dir einen Monatsplan aus.'), false);
      }
      final months = (g.remainingCents / perMonth).ceil();
      return GoalPlan(
          tr('Etwa {x} im Monat, fertig in {months} {y}.', {'x': Money.format(perMonth), 'months': months, 'y': months == 1 ? tr('Monat') : tr('Monaten')}),
          true);
    }
    final share = avgSurplusCents <= 0 ? 999.0 : need / avgSurplusCents;
    if (share <= 0.6) {
      return GoalPlan(tr('{x} im Monat passt in deinen Überschuss.', {'x': Money.format(need)}), true);
    }
    if (share <= 1) {
      return GoalPlan(tr('{x} im Monat ist knapp, fast dein ganzer Überschuss.', {'x': Money.format(need)}), true);
    }
    return GoalPlan(
        tr('{x}/Monat wären nötig. Datum verschieben oder Ziel senken.', {'x': Money.format(need)}),
        false);
  }
}
