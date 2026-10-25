// Realistic sample data so first-time users (and anyone trying the live demo)
// see every screen populated instead of empty states.
//
// Generates six months of everyday German finances up to `now`, a small
// portfolio and budgets for the current month. A fixed random seed keeps the
// data identical on every run, which also makes it testable.
import 'dart:math' as math;
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/budget.dart';
import '../models/goal.dart';
import '../models/holding.dart';
import '../models/recurring.dart';
import '../models/transaction.dart';
import 'db.dart';
import 'goals_service.dart';
import 'recurring_service.dart';
import 'settings_service.dart';

class DemoData {
  static Future<void> load({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final rnd = math.Random(42);
    const uuid = Uuid();

    // random amount in cents between min and max euros
    int amount(double min, double max) => ((min + rnd.nextDouble() * (max - min)) * 100).round();

    Future<void> add(DateTime date, String category, String note, int cents, {bool income = false}) async {
      // never create transactions in the future
      if (date.isAfter(today)) return;
      await DB.addTx(Transaction(
        id: uuid.v4(),
        amountCents: cents,
        category: category,
        date: date,
        isIncome: income,
        note: note,
      ));
    }

    // salary and fixed costs as standing orders; the recurring engine books
    // them for every month, so the "Wiederkehrend" screen is filled as well
    final first = DateTime(today.year, today.month - 5);
    final standing = [
      ['Gehalt', 'Gehalt', 285000, true, 1],
      ['Wohnen', 'Miete', 78000, false, 3],
      ['Transport', 'Deutschlandticket', 5800, false, 2],
      ['Gesundheit', 'Fitnessstudio', 3490, false, 5],
      ['Unterhaltung', 'Netflix', 1399, false, 12],
      ['Unterhaltung', 'Spotify', 1099, false, 20],
    ];
    for (final r in standing) {
      await DB.addRule(RecurringRule(
        id: uuid.v4(),
        category: r[0] as String,
        note: r[1] as String,
        amountCents: r[2] as int,
        isIncome: r[3] as bool,
        interval: 'monatlich',
        startDate: DateTime(first.year, first.month, r[4] as int),
      ));
    }
    await RecurringService.process(today: today);

    for (int m = 5; m >= 0; m--) {
      final month = DateTime(today.year, today.month - m);
      final days = DateTime(month.year, month.month + 1, 0).day;
      DateTime day(int d) => DateTime(month.year, month.month, d.clamp(1, days), 12);
      DateTime randomDay() => day(1 + rnd.nextInt(days));

      // side income every other month
      if (m.isEven) await add(day(15), 'Nebenjob', 'Nachhilfe', 32000, income: true);

      // everyday spending
      const shops = ['REWE', 'EDEKA', 'Lidl', 'Aldi Süd'];
      for (int i = 0; i < 6 + rnd.nextInt(3); i++) {
        await add(randomDay(), 'Lebensmittel', shops[rnd.nextInt(shops.length)], amount(18, 85));
      }
      const food = ['Café', 'Lieferando', 'Restaurant', 'Bäckerei'];
      for (int i = 0; i < 3 + rnd.nextInt(3); i++) {
        await add(randomDay(), 'Essen & Trinken', food[rnd.nextInt(food.length)], amount(6, 45));
      }
      if (rnd.nextBool()) await add(randomDay(), 'Kleidung', 'Zalando', amount(30, 120));
      for (int i = 0; i < 1 + rnd.nextInt(2); i++) {
        await add(randomDay(), 'Sonstiges', 'Amazon', amount(10, 60));
      }
    }

    // a small, diversified portfolio
    final holdings = [
      ['iShares Core MSCI World', 'IWDA.AS', 'ETF', 60.0, 8000, 9500],
      ['iShares Core S&P 500', 'SXR8.DE', 'ETF', 8.0, 48000, 56000],
      ['Apple', 'AAPL', 'Aktie', 10.0, 18000, 26000],
      ['Microsoft', 'MSFT', 'Aktie', 5.0, 33000, 42000],
      ['Bitcoin', 'BTC', 'Krypto', 0.05, 4000000, 5800000],
    ];
    for (final h in holdings) {
      await DB.addHolding(Holding(
        id: uuid.v4(),
        name: h[0] as String,
        symbol: h[1] as String,
        type: h[2] as String,
        shares: h[3] as double,
        buyPriceCents: h[4] as int,
        currentPriceCents: h[5] as int,
      ));
    }

    // budgets for the current month
    final start = DateTime(today.year, today.month, 1);
    final end = DateTime(today.year, today.month + 1, 0);
    for (final b in [['Lebensmittel', 35000], ['Essen & Trinken', 12000], ['Unterhaltung', 4000]]) {
      await DB.addBudget(Budget(
        category: b[0] as String,
        limitCents: b[1] as int,
        startDate: start,
        endDate: end,
      ));
    }

    // two savings goals, one with a date
    if (Hive.isBoxOpen('goals')) {
      await GoalsService.save(Goal(
          id: uuid.v4(), name: 'Urlaub', emoji: '🏖️', targetCents: 120000, savedCents: 45000,
          deadline: DateTime(today.year, today.month + 6, 1), createdAt: today));
      await GoalsService.save(Goal(
          id: uuid.v4(), name: 'Notgroschen', emoji: '🛟', targetCents: 300000, savedCents: 180000,
          createdAt: today));
    }

    // savings from before the six months, so the Kontostand does not start at 0 €
    if (Hive.isBoxOpen('settings')) await Settings.setOpeningBalanceCents(420000);

    await DB.checkBadges();
  }
}
