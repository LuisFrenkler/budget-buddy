import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/contracts.dart';
import 'package:budget_buddy/services/forecast_service.dart';
import 'package:budget_buddy/services/scenario_service.dart';
import 'package:budget_buddy/utils/merchant.dart';

Transaction _t(String note, int cents, DateTime date, {bool income = false, String? cat}) => Transaction(
      id: '$note$date$cents',
      amountCents: cents,
      category: cat ?? (income ? 'Gehalt' : 'Unterhaltung'),
      date: date,
      isIncome: income,
      note: note);

void main() {
  final now = DateTime(2026, 10, 25);

  List<Transaction> monthData() {
    // three full months of salary so income averages; Netflix as fixed Abo
    return [
      for (int m = 7; m <= 9; m++) _t('Gehalt', 300000, DateTime(2026, m, 1), income: true),
      _t('Gehalt', 300000, DateTime(2026, 10, 1), income: true),
      for (int m = 6; m <= 10; m++) _t('Netflix', 1399, DateTime(2026, m, 12)),
      // some variable spend this month (not a contract)
      _t('REWE', 4500, DateTime(2026, 10, 5), cat: 'Lebensmittel'),
      _t('REWE', 3200, DateTime(2026, 10, 18), cat: 'Lebensmittel'),
    ];
  }

  test('excluding an Abo raises freeCents by about the monthly amount', () {
    final tx = monthData();
    expect(Contracts.detect(tx, now: now).any((c) => c.name == 'Netflix'), isTrue);

    final cmp = ScenarioService.compare(
      tx,
      overrides: ForecastOverrides(excludedContractKeys: {Merchant.key('Netflix')}),
      now: now,
    );
    expect(cmp, isNotNull);
    expect(cmp!.deltaFree, 1399);
    expect(cmp.sim.fixedCents, cmp.base.fixedCents - 1399);
  });

  test('a one-time purchase lowers freeCents by that amount', () {
    final tx = monthData();
    final cmp = ScenarioService.compare(
      tx,
      overrides: const ForecastOverrides(oneTimeSpentCents: 5000),
      now: now,
    );
    expect(cmp, isNotNull);
    expect(cmp!.deltaFree, -5000);
    expect(cmp.sim.spentCents, cmp.base.spentCents + 5000);
  });

  test('trimming goals frees the same amount', () {
    final tx = monthData();
    final base = ForecastService.build(tx, now: now)!;
    // pretend goals need 100 € / month via override only on baseline side:
    // compare goalsMonthlyCents: 10000 vs 0
    final withGoals = ForecastService.build(
      tx,
      now: now,
      overrides: const ForecastOverrides(goalsMonthlyCents: 10000),
    )!;
    final without = ForecastService.build(
      tx,
      now: now,
      overrides: const ForecastOverrides(goalsMonthlyCents: 0),
    )!;
    expect(without.freeCents - withGoals.freeCents, 10000);
    expect(base.goalsCents, 0); // no Goal models in this fixture
  });
}
