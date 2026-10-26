import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/contracts.dart';

Transaction _t(String note, int cents, DateTime date, {bool income = false}) => Transaction(
    id: '$note$date', amountCents: cents, category: 'Unterhaltung', date: date, isIncome: income, note: note);

void main() {
  final now = DateTime(2026, 10, 25);

  test('finds a monthly subscription', () {
    final tx = [for (int m = 6; m <= 10; m++) _t('Netflix', 1399, DateTime(2026, m, 12))];
    final c = Contracts.detect(tx, now: now);
    expect(c.single.name, 'Netflix');
    expect(c.single.monthlyCents, 1399);
    expect(c.single.nextDate, DateTime(2026, 11, 12));
  });

  test('ignores frequent shopping at the same store', () {
    final tx = [
      for (int d = 1; d <= 28; d += 3) _t('REWE', 2500 + d * 100, DateTime(2026, 10, d)),
    ];
    expect(Contracts.detect(tx, now: now), isEmpty);
  });

  test('ignores payments with very different amounts', () {
    final tx = [
      _t('Amazon', 1000, DateTime(2026, 7, 5)),
      _t('Amazon', 8000, DateTime(2026, 8, 5)),
      _t('Amazon', 3000, DateTime(2026, 9, 5)),
    ];
    expect(Contracts.detect(tx, now: now), isEmpty);
  });

  test('ignores ended contracts and income', () {
    final ended = [for (int m = 1; m <= 4; m++) _t('Altes Abo', 999, DateTime(2026, m, 3))];
    final salary = [for (int m = 7; m <= 10; m++) _t('Gehalt', 300000, DateTime(2026, m, 1), income: true)];
    expect(Contracts.detect([...ended, ...salary], now: now), isEmpty);
  });

  test('reports a price increase', () {
    final tx = [
      _t('Spotify', 1099, DateTime(2026, 8, 20)),
      _t('Spotify', 1099, DateTime(2026, 9, 20)),
      _t('Spotify', 1199, DateTime(2026, 10, 20)),
    ];
    final c = Contracts.detect(tx, now: now).single;
    expect(c.priceChange, 100);
    expect(Contracts.monthlyTotal([c]), 1199);
  });

  test('a big price rise is reported, not hidden', () {
    final tx = [
      for (int m = 6; m <= 9; m++) _t('Netflix', 1399, DateTime(2026, m, 12)),
      _t('Netflix', 1799, DateTime(2026, 10, 12)),
    ];
    final c = Contracts.detect(tx, now: now).single;
    expect(c.priceChange, 400);
    expect(c.monthlyCents, 1799);
  });

  test('one skipped debit does not end a contract', () {
    final tx = [
      _t('Fitness', 3490, DateTime(2026, 6, 5)),
      _t('Fitness', 3490, DateTime(2026, 7, 5)),
      // August skipped, September carries on
      _t('Fitness', 3490, DateTime(2026, 9, 5)),
      _t('Fitness', 3490, DateTime(2026, 10, 5)),
    ];
    expect(Contracts.detect(tx, now: now).single.name, 'Fitness');
  });

  test('an old irregularity is forgiven, a recent one is not', () {
    final old = [
      _t('Handy', 1500, DateTime(2026, 1, 3)),
      _t('Handy', 1500, DateTime(2026, 1, 20)), // years ago a duplicate
      for (int m = 2; m <= 10; m++) _t('Handy', 1500, DateTime(2026, m, 3)),
    ];
    expect(Contracts.detect(old, now: now).single.name, 'Handy');
  });

  test('next date stays inside short months', () {
    final tx = [for (int m = 8; m <= 10; m++) _t('Miete', 89000, DateTime(2026, m, m == 9 ? 30 : 31))];
    final c = Contracts.detect(tx, now: DateTime(2026, 11, 1)).single;
    expect(c.nextDate, DateTime(2026, 11, 30));
  });
}
