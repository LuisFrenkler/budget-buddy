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

  test('before sign-up the refund check becomes the agent finds, oldest deadline first by amount', () async {
    expect(AheadAgent.guestFinds(now: today), isEmpty);
    await Hive.box('settings').put('refundCheck', {'startYear': 2022, 'startMonth': 9, 'grossMonth': 3000.0, 'km': 0.0});
    final finds = AheadAgent.guestFinds(now: today);
    // 2022: four months worked, the wage tax ran for twelve; the running year is not a find
    expect(finds.first.year, 2022);
    expect(finds.first.cents, greaterThan(0));
    expect(finds.first.text, contains('44'));
    expect(finds.any((f) => f.year == 2026), isFalse);
    expect(AheadAgent.upToCents(finds), greaterThanOrEqualTo(AheadAgent.openCents(finds)));
  });

  test('the start is never empty: check finds before adoption, the running year, one look at the contracts', () async {
    await Hive.box('settings').put('refundCheck', {'startYear': 2022, 'startMonth': 9, 'grossMonth': 3000.0, 'km': 20.0});
    // right after sign-up, before the check is adopted, the same finds show
    final before = AheadAgent.run(tx: const [], now: today);
    expect(before.first.id, 'tax-2022');
    expect(before.any((f) => f.id == 'tax-check'), isFalse);
    await TaxEstimate.adoptRefundCheck(now: today);
    final after = AheadAgent.run(tx: const [], now: today);
    expect(after.first.id, 'tax-2022');
    expect(after.first.cents, before.first.cents);
    // the running year cannot be filed yet: it waits and is no money found
    final running = after.firstWhere((f) => f.year == 2026);
    expect(running.kind, FindKind.waiting);
    expect(AheadAgent.openCents(after), AheadAgent.openCents(before));

    final netflix = [
      for (final m in [8, 9, 10, 11])
        Transaction(id: 'n$m', amountCents: 1399, category: 'Unterhaltung', isIncome: false, date: DateTime(2026, m, 3), note: 'Netflix'),
    ];
    final rent = [
      for (final m in [8, 9, 10, 11])
        Transaction(id: 'r$m', amountCents: 78000, category: 'Wohnen', isIncome: false, date: DateTime(2026, m, 1), note: 'Miete'),
    ];
    // the rent alone is nothing to go through, and it stays out of the sum
    expect(AheadAgent.run(tx: rent, now: today).any((f) => f.id == 'contracts'), isFalse);
    final contracts = AheadAgent.run(tx: [...netflix, ...rent], now: today).firstWhere((f) => f.id == 'contracts');
    expect(contracts.title, startsWith('Netflix '));
    expect(contracts.kind, FindKind.money);
    // a look, not money found: no amount for the headline
    expect(contracts.cents, isNull);
    expect(contracts.question, isNotNull);
    // a real trap wins over the look
    const hint = Hint('still-x', HintKind.stillCharging, 'X bucht weiter', 'trotz Kündigung', HintTarget.contracts, cents: 999);
    expect(AheadAgent.run(tx: netflix, hints: [hint], now: today).any((f) => f.id == 'contracts'), isFalse);
    await AheadAgent.snooze('contracts', now: today);
    expect(AheadAgent.run(tx: netflix, now: today).any((f) => f.id == 'contracts'), isFalse);
  });

  test('a refund check with little in it is still a check: Ahead does not say it has not looked', () async {
    // full years, no commute: every open year stays under the 50 € a find needs
    await Hive.box('settings').put('refundCheck', {'startYear': 2022, 'startMonth': 1, 'grossMonth': 3000.0, 'km': 0.0});
    expect(AheadAgent.run(tx: const [], now: today).any((f) => f.id == 'tax-check'), isFalse);
    await TaxEstimate.adoptRefundCheck(now: today);
    expect(AheadAgent.run(tx: const [], now: today).any((f) => f.id == 'tax-check'), isFalse);
  });

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

  test('the guarantee counts from the day of joining: only money that arrived on or after it', () async {
    await TaxEstimate.markFiled(2023, 900, at: DateTime(2026, 9, 1));
    await TaxEstimate.saveAssessment(Assessment(year: 2023, refund: 812.40, date: DateTime(2026, 11, 2)));
    expect(AheadAgent.recoveredCents(tx: const [], now: today, since: DateTime(2026, 11, 2, 18)), 81240);
    expect(AheadAgent.recoveredCents(tx: const [], now: today, since: DateTime(2026, 11, 3)), 0);

    final gym = [
      for (var m = 3; m <= 7; m++)
        Transaction(id: 'g$m', amountCents: 2990, category: 'Freizeit', isIncome: false, date: DateTime(2026, m, 1), note: 'FitX Studio'),
      Transaction(id: 'c', amountCents: 350, category: 'Essen', isIncome: false, date: DateTime(2026, 11, 15), note: 'Bäcker'),
    ];
    await CancellationService.markSent('FitX Studio', at: DateTime(2026, 7, 10));
    // August to November did not come; joined on 1 October: October and November count, next to the refund
    expect(AheadAgent.recoveredCents(tx: gym, now: today, since: DateTime(2026, 10, 1)), 81240 + 2 * 2990);
    expect(AheadAgent.recoveredCents(tx: gym, now: today, since: DateTime(2026, 10, 2)), 81240 + 2990);
    expect(AheadAgent.recoveredCents(tx: gym, now: today, since: DateTime(2026, 11, 3)), 0);
    expect(AheadAgent.recoveredCents(tx: gym, now: today), 81240 + 4 * 2990);
  });

  test('a double charge counts once the same merchant paid the same amount back', () {
    Transaction t(String id, int day, {bool income = false, String note = 'PAYPAL *SPOTIFY', int cents = 1799}) =>
        Transaction(id: id, amountCents: cents, category: 'Abos', isIncome: income, date: DateTime(2026, 10, day), note: note);
    final twice = [t('a', 5), t('b', 6)];
    expect(AheadAgent.recoveredCents(tx: twice, now: today), 0);
    expect(AheadAgent.recoveredCents(tx: [...twice, t('r', 20, income: true, note: 'Spotify')], now: today), 1799);
    // one double, one refund: a second booking is not a second reclaim
    expect(AheadAgent.recoveredCents(tx: [...twice, t('r', 20, income: true), t('r2', 21, income: true)], now: today), 1799);
    // another amount, another merchant, money that came before the charge, or no double at all: not proven
    expect(AheadAgent.recoveredCents(tx: [...twice, t('r', 20, income: true, cents: 1800)], now: today), 0);
    expect(AheadAgent.recoveredCents(tx: [...twice, t('r', 20, income: true, note: 'Netflix')], now: today), 0);
    expect(AheadAgent.recoveredCents(tx: [...twice, t('r', 4, income: true)], now: today), 0);
    expect(AheadAgent.recoveredCents(tx: [t('a', 5), t('r', 20, income: true)], now: today), 0);
    // before joining: not the guarantee's money
    expect(AheadAgent.recoveredCents(tx: [...twice, t('r', 20, income: true)], now: today, since: DateTime(2026, 10, 21)), 0);
    expect(AheadAgent.recoveredCents(tx: [...twice, t('r', 20, income: true)], now: today, since: DateTime(2026, 10, 20)), 1799);
  });

  test('the guarantee has three steps: nothing, under twice the yearly fee, reached', () {
    expect(AheadAgent.guaranteeCents, 2 * AheadAgent.yearlyFeeCents);
    expect(AheadAgent.guaranteeTier(0), GuaranteeTier.nothing);
    expect(AheadAgent.guaranteeTier(9799), GuaranteeTier.under);
    expect(AheadAgent.guaranteeTier(9800), GuaranteeTier.reached);
  });

  test('a price rise carries its contract so the letter can open; a sent letter ends the find', () async {
    final netflix = [
      for (final m in [8, 9, 10, 11])
        Transaction(id: 'n$m', amountCents: m == 11 ? 1599 : 1399, category: 'Unterhaltung', isIncome: false, date: DateTime(2026, m, 3), note: 'Netflix'),
    ];
    // the real hint, so a changed hint id shows here
    final hints = HintsService.current(tx: netflix, budgets: const [], goals: const [], now: today);
    final rise = AheadAgent.run(tx: netflix, hints: hints, now: today).firstWhere((f) => f.id.startsWith('price-'));
    expect(rise.contract, 'Netflix');
    // a find about no contract goes to the conversation
    const twice = Hint('double-x', HintKind.doubleCharge, 'X zweimal abgebucht?', '', HintTarget.buddy, cents: 500);
    expect(AheadAgent.run(tx: netflix, hints: const [twice], now: today).firstWhere((f) => f.id == 'double-x').contract, isNull);
    await CancellationService.markSent('Netflix', at: today);
    expect(AheadAgent.run(tx: netflix, hints: hints, now: today).any((f) => f.id.startsWith('price-')), isFalse);
  });

  test('money hints become finds, other hints stay out, Später hides for a week', () async {
    const price = Hint('price-x', HintKind.priceUp, 'Netflix ist teurer geworden', '+2 € im Monat', HintTarget.contracts,
        cents: 2400, yearly: true);
    const budget = Hint('budget-x', HintKind.budgetOver, 'Essen: Budget überschritten', '', HintTarget.buddy);
    var finds = AheadAgent.run(tx: const [], hints: const [price, budget], now: today);
    expect(finds.where((f) => f.kind == FindKind.money).map((f) => f.id), ['price-x']);
    final rise = finds.firstWhere((f) => f.id == 'price-x');
    expect(rise.question, contains('Netflix'));
    expect((rise.cents, rise.yearly), (2400, true));
    // a cost per year is saved, not paid back: its own line, never in the big number
    expect(AheadAgent.openCents(finds), 0);
    expect(AheadAgent.upToCents(finds), 0);
    expect(AheadAgent.yearlyCents(finds), 2400);
    // money to reclaim is the big number
    const still = Hint('still-x', HintKind.stillCharging, 'X bucht weiter', 'trotz Kündigung', HintTarget.contracts, cents: 999);
    finds = AheadAgent.run(tx: const [], hints: const [price, still], now: today);
    expect((AheadAgent.openCents(finds), AheadAgent.yearlyCents(finds)), (999, 2400));

    await AheadAgent.snooze('price-x', now: today);
    finds = AheadAgent.run(tx: const [], hints: const [price], now: today);
    expect(finds.any((f) => f.id == 'price-x'), isFalse);
    finds = AheadAgent.run(tx: const [], hints: const [price], now: today.add(const Duration(days: 8)));
    expect(finds.any((f) => f.id == 'price-x'), isTrue);
  });
}
