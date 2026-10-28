import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/holding.dart';
import 'package:budget_buddy/services/vorsorge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gap closes when statutory covers desired', () {
    final r = Vorsorge.build(
      input: const VorsorgeInput(
        age: 40,
        retireAge: 67,
        desiredNetCents: 150000,
        statutoryCents: 160000,
        extraCapitalCents: 0,
      ),
      holdings: const [],
      goals: const [],
    );
    expect(r.gapClosed, isTrue);
    expect(r.gapMonthlyCents, 0);
  });

  test('capital defaults to depot only; goals opt-in and skip Notgroschen', () {
    final holdings = [
      Holding(
        id: 'h1',
        name: 'ETF',
        symbol: '',
        type: 'ETF',
        shares: 10,
        buyPriceCents: 10000,
        currentPriceCents: 10000,
      ),
    ];
    final goals = [
      Goal(id: 'g1', name: 'Notgroschen', emoji: '🛟', targetCents: 500000, savedCents: 200000, createdAt: DateTime(2026)),
      Goal(id: 'g2', name: 'Urlaub', emoji: '✈️', targetCents: 100000, savedCents: 50000, createdAt: DateTime(2026)),
    ];
    final depotOnly = Vorsorge.build(
      input: const VorsorgeInput(age: 35, retireAge: 67, desiredNetCents: 200000, statutoryCents: 100000),
      holdings: holdings,
      goals: goals,
    );
    expect(depotOnly.capitalCents, 100000); // goals off by default
    final withGoals = Vorsorge.build(
      input: const VorsorgeInput(
          age: 35, retireAge: 67, desiredNetCents: 200000, statutoryCents: 100000, includeGoals: true),
      holdings: holdings,
      goals: goals,
    );
    expect(withGoals.capitalCents, 100000 + 50000); // Urlaub only, not Notgroschen
    expect(withGoals.gapMonthlyCents, greaterThan(0));
    expect(withGoals.saveExtraMonthlyCents, greaterThan(0));
  });

  test('estimate from net is roughly 45 percent', () {
    expect(Vorsorge.estimateStatutoryFromNet(300000), 135000);
  });
}
