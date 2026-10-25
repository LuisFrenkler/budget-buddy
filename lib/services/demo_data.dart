// Realistic sample data so first-time users (and anyone trying the live demo)
// see every screen populated instead of empty states.
//
// Generates six months of everyday German finances up to `now`, a small
// portfolio and budgets for the current month. A fixed random seed keeps the
// data identical on every run, which also makes it testable.
import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import '../models/budget.dart';
import '../models/holding.dart';
import '../models/transaction.dart';
import 'db.dart';

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

    for (int m = 5; m >= 0; m--) {
      final month = DateTime(today.year, today.month - m);
      final days = DateTime(month.year, month.month + 1, 0).day;
      DateTime day(int d) => DateTime(month.year, month.month, d.clamp(1, days), 12);
      DateTime randomDay() => day(1 + rnd.nextInt(days));

      // income
      await add(day(1), 'Gehalt', 'Gehalt', 285000, income: true);
      if (m.isEven) await add(day(15), 'Nebenjob', 'Nachhilfe', 32000, income: true);

      // fixed costs
      await add(day(3), 'Wohnen', 'Miete', 78000);
      await add(day(2), 'Transport', 'Deutschlandticket', 5800);
      await add(day(5), 'Gesundheit', 'Fitnessstudio', 3490);
      await add(day(12), 'Unterhaltung', 'Netflix', 1399);
      await add(day(20), 'Unterhaltung', 'Spotify', 1099);

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

    await DB.checkBadges();
  }
}
