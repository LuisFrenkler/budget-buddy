// Ahead as an agent: what it finds on its own, what it counts as money back,
// and that "Später" really puts a find away for a week.
import 'dart:io';

import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/ahead_agent.dart';
import 'package:budget_buddy/services/cancellation_service.dart';
import 'package:budget_buddy/services/hints_service.dart';
import 'package:budget_buddy/services/tax_estimate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  final today = DateTime(2026, 11, 17);

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('ahead_agent').path);
    await Hive.openBox('settings');
  });
  setUp(() async => Hive.box('settings').clear());

  test('no tax answers yet: the first job is to check', () {
    final finds = AheadAgent.run(tx: const [], now: today);
    expect(finds.single.id, 'tax-check');
    expect(finds.single.year, isNull);
  });

  test('an open year with answers becomes a find with the least it brings and the deadline', () async {
    await TaxEstimate.saveProfile(const TaxProfile(grossMonth: 3000, monthsWorked: 4, km: 20), year: 2022);
    final finds = AheadAgent.run(tx: const [], now: today);
    final y2022 = finds.firstWhere((f) => f.year == 2022);
    expect(y2022.kind, FindKind.tax);
    expect(y2022.cents, greaterThan(0));
    // 44 days left: the deadline is in the text
    expect(y2022.text, contains('44'));
    expect(finds.any((f) => f.id == 'tax-check'), isFalse);
    expect(AheadAgent.openCents(finds), greaterThanOrEqualTo(y2022.cents!));
  });

  test('filed years wait for the notice, a recent notice is done and counts as money back', () async {
    await TaxEstimate.saveProfile(const TaxProfile(grossMonth: 3000, monthsWorked: 4), year: 2023);
    await TaxEstimate.markFiled(2023, 900, at: DateTime(2026, 9, 1));
    expect(AheadAgent.run(tx: const [], now: today).firstWhere((f) => f.year == 2023).kind, FindKind.waiting);

    await TaxEstimate.saveAssessment(Assessment(year: 2023, refund: 812.40, date: DateTime(2026, 11, 2)));
    final done = AheadAgent.run(tx: const [], now: today).firstWhere((f) => f.year == 2023);
    expect(done.kind, FindKind.done);
    expect(AheadAgent.recoveredCents(tx: const [], now: today), 81240);
    // a back payment is no money found, nor a refund for a year filed without Ahead
    await TaxEstimate.saveAssessment(Assessment(year: 2024, refund: -120, date: DateTime(2026, 11, 2)));
    await TaxEstimate.saveAssessment(Assessment(year: 2022, refund: 300, date: DateTime(2026, 11, 2)));
    expect(AheadAgent.recoveredCents(tx: const [], now: today), 81240);
  });

  test('a cancelled contract counts every monthly debit that stopped coming, as far as the bookings reach', () async {
    final gym = [
      for (var m = 3; m <= 7; m++)
        Transaction(id: 'g$m', amountCents: 2990, category: 'Freizeit', isIncome: false, date: DateTime(2026, m, 1), note: 'FitX Studio'),
    ];
    final coffee = Transaction(id: 'c', amountCents: 350, category: 'Essen', isIncome: false, date: DateTime(2026, 11, 15), note: 'Bäcker');
    await CancellationService.markSent('FitX Studio', at: DateTime(2026, 7, 10));
    // last debit 1 July, bookings up to mid-November: August to November did not come
    expect(AheadAgent.recoveredCents(tx: [...gym, coffee], now: today), 4 * 2990);
    // no bookings since September (other bank, no import): only August and September are proven
    final sept = Transaction(id: 's', amountCents: 350, category: 'Essen', isIncome: false, date: DateTime(2026, 9, 20), note: 'Bäcker');
    expect(AheadAgent.recoveredCents(tx: [...gym, sept], now: today), 2 * 2990);
    // one last debit in the notice period: saved from September on
    final notice = [...gym, coffee, Transaction(id: 'g8', amountCents: 2990, category: 'Freizeit', isIncome: false, date: DateTime(2026, 8, 1), note: 'FitX Studio')];
    expect(AheadAgent.recoveredCents(tx: notice, now: today), 3 * 2990);
    // still charging: nothing saved
    final charged = [
      ...notice,
      for (var m = 9; m <= 11; m++)
        Transaction(id: 'h$m', amountCents: 2990, category: 'Freizeit', isIncome: false, date: DateTime(2026, m, 1), note: 'FitX Studio'),
    ];
    expect(AheadAgent.recoveredCents(tx: charged, now: today), 0);
    // a yearly plan is not twelve monthly savings
    await CancellationService.markSent('Adobe', at: DateTime(2026, 3, 10));
    final yearly = [
      Transaction(id: 'a1', amountCents: 23988, category: 'Abos', isIncome: false, date: DateTime(2025, 3, 1), note: 'Adobe'),
      Transaction(id: 'a2', amountCents: 23988, category: 'Abos', isIncome: false, date: DateTime(2026, 3, 1), note: 'Adobe'),
    ];
    expect(AheadAgent.recoveredCents(tx: [...gym, ...yearly, coffee], now: today), 4 * 2990);
  });

  test('money hints become finds, other hints stay out, Später hides for a week', () async {
    const price = Hint('price-x', HintKind.priceUp, 'Netflix ist teurer geworden', '+2 € im Monat', HintTarget.contracts);
    const budget = Hint('budget-x', HintKind.budgetOver, 'Essen: Budget überschritten', '', HintTarget.buddy);
    var finds = AheadAgent.run(tx: const [], hints: const [price, budget], now: today);
    expect(finds.where((f) => f.kind == FindKind.money).map((f) => f.id), ['price-x']);
    expect(finds.firstWhere((f) => f.id == 'price-x').question, contains('Netflix'));

    await AheadAgent.snooze('price-x', now: today);
    finds = AheadAgent.run(tx: const [], hints: const [price], now: today);
    expect(finds.any((f) => f.id == 'price-x'), isFalse);
    finds = AheadAgent.run(tx: const [], hints: const [price], now: today.add(const Duration(days: 8)));
    expect(finds.any((f) => f.id == 'price-x'), isTrue);
  });
}
