import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/categorizer.dart';
import 'package:budget_buddy/services/contracts.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/forecast_service.dart';
import 'package:budget_buddy/utils/theme.dart';

Transaction _t(String id, int cents, String category, DateTime date, {bool income = false, String? note}) =>
    Transaction(id: id, amountCents: cents, category: category, date: date, isIncome: income, note: note);

void main() {
  final now = DateTime(2026, 10, 21);
  final tx = [
    for (var m = 7; m <= 10; m++) _t('s$m', 250000, 'Gehalt', DateTime(2026, m, 1), income: true, note: 'Gehalt'),
    // 500 € to the savings account every month, and once 200 € back
    for (var m = 7; m <= 10; m++) _t('u$m', 50000, Categories.transfer, DateTime(2026, m, 2), note: 'Tagesgeld'),
    _t('back', 20000, Categories.transfer, DateTime(2026, 10, 5), income: true, note: 'Tagesgeld'),
    _t('food', 30000, 'Lebensmittel', DateTime(2026, 10, 10)),
  ];

  test('a transfer to savings is neither spending nor income', () {
    final oct = DB.inMonth(tx, now);
    expect(DB.sumOf(oct, isIncome: false), 30000);
    expect(DB.sumOf(oct, isIncome: true), 250000);
    expect(DB.categoriesOf(oct, isIncome: false).keys, ['Lebensmittel']);
  });

  test('it is no contract and no spending in the forecast', () {
    expect(Contracts.detect(tx, now: now), isEmpty);
    final f = ForecastService.build(tx, now: now)!;
    expect(f.incomeCents, 250000);
    expect(f.spentCents, 30000);
  });

  test('bank bookings to savings and brokers are recognised', () {
    expect(Categorizer.guess('Überweisung Tagesgeld ING', isIncome: false), Categories.transfer);
    expect(Categorizer.guess('Trade Republic Bank GmbH Sparplan', isIncome: false), Categories.transfer);
    expect(Categorizer.guess('Umbuchung vom Sparkonto', isIncome: true), Categories.transfer);
    expect(Categorizer.guess('REWE Markt', isIncome: false), 'Lebensmittel');
  });
}
