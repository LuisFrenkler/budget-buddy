// Yearly and quarterly payments as a monthly reserve in the forecast.
import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/forecast_service.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String id, double eur, String cat, DateTime d, String note, {bool income = false}) =>
    Transaction(id: id, amountCents: (eur * 100).round(), category: cat, date: d, isIncome: income, note: note);

void main() {
  final now = DateTime(2026, 11, 14);
  final base = [
    for (final m in [8, 9, 10]) _t('g$m', 2000, 'Gehalt', DateTime(2026, m, 28), 'Firma', income: true),
    _t('k', 480, 'Sonstiges', DateTime(2025, 12, 1), 'HUK Kfz-Versicherung'),
  ];

  test('the car insurance takes 40 € a month off what is free', () {
    final f = ForecastService.build(base, now: now)!;
    expect(f.reserveCents, 4000);
    expect(f.freeCents, 200000 - 4000);
    expect(f.variableBudgetCents, 200000 - 4000);
  });

  test('a reserve goal of its own carries it already', () {
    final goal = Goal(id: 'r', name: 'Rücklage Auto', emoji: '🚗', targetCents: 48000, createdAt: DateTime(2026), monthlyCents: 4000);
    final f = ForecastService.build(base, goals: [goal], now: now)!;
    expect(f.reserveCents, 0);
    expect(f.goalsCents, 4000);
  });

  test('the month it lands in is paid from the reserve, not from the month', () {
    final tx = [
      for (final m in [8, 9, 10]) _t('g$m', 2000, 'Gehalt', DateTime(2026, m, 28), 'Firma', income: true),
      _t('k1', 480, 'Sonstiges', DateTime(2025, 11, 2), 'HUK Kfz-Versicherung'),
      _t('k2', 480, 'Sonstiges', DateTime(2026, 11, 2), 'HUK Kfz-Versicherung'),
    ];
    // last year's payment and this one: a yearly rhythm, spent this month stays 0
    final f = ForecastService.build(tx, now: now)!;
    expect(f.spentCents, 0);
    expect(f.reserveCents, 4000);
  });
}
