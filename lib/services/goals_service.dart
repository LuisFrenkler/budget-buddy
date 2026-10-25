// Savings goals in the 'goals' Hive box, plus Buddy's plan for each: how
// much per month it takes, and whether the usual monthly surplus covers it.
import 'package:hive/hive.dart';
import '../models/goal.dart';
import '../utils/money.dart';

class GoalPlan {
  final String text;
  final bool onTrack;
  const GoalPlan(this.text, this.onTrack);
}

class GoalsService {
  static Box get _box => Hive.box('goals');

  static List<Goal> all() {
    final list = <Goal>[];
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
    if (g.reached) return const GoalPlan('Geschafft! Zeit für das nächste Ziel.', true);
    final need = g.monthlyNeeded(today);
    if (need == null) {
      if (avgSurplusCents <= 0) {
        return const GoalPlan('Gib dem Ziel ein Datum, dann rechne ich dir einen Plan aus.', false);
      }
      // without a date: how long at half of the usual surplus
      // rounded down to full 10 €, a number people actually set up
      final perMonth = (avgSurplusCents ~/ 2 ~/ 1000) * 1000;
      if (perMonth <= 0) {
        return const GoalPlan('Gib dem Ziel ein Datum, dann rechne ich dir einen Plan aus.', false);
      }
      final months = (g.remainingCents / perMonth).ceil();
      return GoalPlan(
          'Mit ${Money.format(perMonth)} im Monat, der Hälfte deines üblichen Überschusses, '
          'hast du es in $months ${months == 1 ? 'Monat' : 'Monaten'}.',
          true);
    }
    final share = avgSurplusCents <= 0 ? 999.0 : need / avgSurplusCents;
    if (share <= 0.6) {
      return GoalPlan('Leg ${Money.format(need)} im Monat zurück. Das passt locker in deinen Überschuss.', true);
    }
    if (share <= 1) {
      return GoalPlan(
          'Leg ${Money.format(need)} im Monat zurück. Das ist knapp: fast dein ganzer Überschuss.', true);
    }
    return GoalPlan(
        'Dafür bräuchtest du ${Money.format(need)} im Monat, mehr als du im Schnitt übrig hast. '
        'Verschieb das Datum oder senk den Betrag.',
        false);
  }
}
