// What-if on the same forecast formula: baseline vs a temporary override.
// Nothing is persisted, only for the Monats-Simulator sheet and offline Buddy.
import '../models/goal.dart';
import '../models/transaction.dart';
import 'forecast_service.dart';

class ScenarioCompare {
  final MonthForecast base;
  final MonthForecast sim;
  final int deltaFree;

  const ScenarioCompare({
    required this.base,
    required this.sim,
    required this.deltaFree,
  });

  int get deltaPerDay => sim.perDayCents - base.perDayCents;
}

class ScenarioService {
  static ScenarioCompare? compare(
    List<Transaction> tx, {
    required ForecastOverrides overrides,
    List<Goal> goals = const [],
    int? balanceCents,
    DateTime? now,
  }) {
    final base = ForecastService.build(tx, goals: goals, now: now, balanceCents: balanceCents);
    if (base == null) return null;
    final sim = ForecastService.build(
      tx,
      goals: goals,
      now: now,
      balanceCents: balanceCents,
      overrides: overrides,
    );
    if (sim == null) return null;
    return ScenarioCompare(base: base, sim: sim, deltaFree: sim.freeCents - base.freeCents);
  }
}
