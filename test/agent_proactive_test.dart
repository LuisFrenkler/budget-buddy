// The agent acts on its own: what burns leads the start, every find ends in
// something Ahead does, the next step never repeats a find, the salary gets a
// plan, and the phone hears of each urgent find once.
import 'dart:io';

import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/ahead_agent.dart';
import 'package:budget_buddy/services/buddy_log.dart';
import 'package:budget_buddy/services/buddy_tips.dart';
import 'package:budget_buddy/services/hints_service.dart';
import 'package:budget_buddy/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

Transaction _t(String id, double eur, String category, DateTime date, {bool income = false, String? note, String? raw}) =>
    Transaction(id: id, amountCents: (eur * 100).round(), category: category, date: date, isIncome: income, note: note, raw: raw);

// salary on the 28th, rent on the 1st, phone on the 20th, 15 € a day of groceries,
// and Netflix on the 3rd, 2 € more since November
List<Transaction> _ledger() => [
      for (final m in [8, 9, 10]) ...[
        _t('g$m', 2400, 'Gehalt', DateTime(2026, m, 28), income: true, note: 'Hapag-Lloyd'),
        _t('m$m', 750, 'Wohnen', DateTime(2026, m, 1), note: 'Miete'),
        _t('h$m', 30, 'Sonstiges', DateTime(2026, m, 20), note: 'Telekom'),
      ],
      _t('m11', 750, 'Wohnen', DateTime(2026, 11, 1), note: 'Miete'),
      for (final m in [8, 9, 10, 11]) _t('n$m', m == 11 ? 15.99 : 13.99, 'Unterhaltung', DateTime(2026, m, 3), note: 'Netflix'),
      for (var d = 0; d < 90; d++) _t('l$d', 15, 'Lebensmittel', DateTime(2026, 11, 14).subtract(Duration(days: d + 1)), note: 'Rewe'),
    ];

void main() {
  final now = DateTime(2026, 11, 14);
  late Box box;

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('agent_proactive').path);
    box = await Hive.openBox('settings');
  });
  setUp(() async => box.clear());

  List<Hint> hints(List<Transaction> tx, {int? balance = 20000, DateTime? at}) =>
      HintsService.current(tx: tx, budgets: const [], goals: const [], balanceCents: balance, now: at ?? now);

  test('what burns leads, then the monthly loss, then the tax year; each find ends in an action', () async {
    await box.put('refundCheck', {'startYear': 2022, 'startMonth': 9, 'grossMonth': 3000.0, 'km': 0.0});
    final tx = _ledger();
    final finds = AheadAgent.run(tx: tx, hints: hints(tx), now: now);
    expect(finds[0].id, startsWith('overdraft-'));
    expect(finds[1].id, startsWith('price-'));
    expect(finds[2].id, 'tax-2022');
    // the number is in the title, as an estimate; it is nothing to "get back", so no amount for the headline
    expect(finds[0].title, 'Bis zum Gehalt fehlen etwa 40,00\u00a0€');
    expect(finds[0].cents, isNull);
    expect(finds[0].question, allOf(contains('Plan'), contains('40,00')));
    expect(finds[1].contract, 'Netflix');
    for (final f in finds.where((f) => f.kind == FindKind.money)) {
      expect(f.question ?? f.contract, isNotNull, reason: f.id);
    }

    // a year that ends within 30 days burns too: before the monthly loss
    final dec = DateTime(2026, 12, 5);
    final late = AheadAgent.run(tx: tx, hints: hints(tx, balance: null, at: dec), now: dec);
    expect(late.first.id, 'tax-2022');

    // three monthly losses do not push the refund off the start
    const still = Hint('still-x', HintKind.stillCharging, 'X bucht weiter', '', HintTarget.contracts, cents: 999);
    const price = Hint('price-x', HintKind.priceUp, 'Y ist teurer', '', HintTarget.contracts, cents: 2400, yearly: true);
    const twice = Hint('double-x', HintKind.doubleCharge, 'Z zweimal', '', HintTarget.buddy, cents: 500);
    const back = Hint('returned-x', HintKind.returnedDebit, 'Lastschrift ging zurück', '', HintTarget.buddy, question: 'q');
    final many = AheadAgent.run(tx: const [], hints: const [still, price, twice, back], now: now);
    expect(many.take(4).map((f) => f.id), ['returned-x', 'still-x', 'tax-2022', 'price-x']);
  });

  test('a find is gone once the person acted, and after "Später"', () async {
    final tx = _ledger();
    bool overdraft(List<Hint> h) => AheadAgent.run(tx: tx, hints: h, now: now).any((f) => f.id.startsWith('overdraft-'));
    expect(overdraft(hints(tx)), isTrue);
    // the balance topped up
    expect(overdraft(hints(tx, balance: 30000)), isFalse);
    // put off for a week
    await AheadAgent.snooze(hints(tx).firstWhere((h) => h.kind == HintKind.overdraft).id, now: now);
    expect(overdraft(hints(tx)), isFalse);
    expect(AheadAgent.run(tx: tx, hints: hints(tx), now: now.add(const Duration(days: 8))).first.id, startsWith('overdraft-'));
    await box.clear();

    // a debit bounced: a find until the bill is paid again
    final bounced = [
      _t('d', 89.90, 'Sonstiges', DateTime(2026, 11, 5), note: 'Vodafone', raw: 'SEPA Lastschrift Vodafone'),
      _t('b', 89.90, 'Sonstiges', DateTime(2026, 11, 6), income: true, note: 'Vodafone', raw: 'Rücklastschrift'),
    ];
    final find = AheadAgent.run(tx: bounced, hints: hints(bounced), now: now).first;
    expect(find.id, 'returned-b');
    expect(find.question, contains('Erinnere mich'));
    final paid = [...bounced, _t('p', 89.90, 'Sonstiges', DateTime(2026, 11, 10), note: 'Vodafone')];
    expect(AheadAgent.run(tx: paid, hints: hints(paid), now: now).any((f) => f.id == 'returned-b'), isFalse);
  });

  test('the next step never says what a find on the start already says', () {
    final tx = _ledger();
    final all = hints(tx, balance: 30000);
    expect(AheadAgent.run(tx: tx, hints: all, now: now).take(3).any((f) => f.contract == 'Netflix'), isTrue);
    final tip = BuddyTips.pick(tx: tx, budgets: const [], now: now, hints: all);
    expect(tip?.text ?? '', isNot(contains('Netflix')));

    // the contracts are laid out as a find: no "du hast drei Verträge" below it
    final three = [
      for (final m in [8, 9, 10, 11]) ...[
        _t('a$m', 13.99, 'Unterhaltung', DateTime(2026, m, 3), note: 'Netflix'),
        _t('b$m', 9.99, 'Unterhaltung', DateTime(2026, m, 5), note: 'Spotify'),
        _t('c$m', 29.90, 'Gesundheit', DateTime(2026, m, 7), note: 'FitX'),
      ],
    ];
    expect(AheadAgent.run(tx: three, hints: hints(three), now: now).any((f) => f.id == 'contracts'), isTrue);
    expect(BuddyTips.pick(tx: three, budgets: const [], now: now, hints: hints(three))?.text ?? '', isNot(contains('Verträge')));
  });

  test('the salary moment: a plan from the own numbers, until the next visit or until money is put aside', () async {
    final tx = [..._ledger(), _t('g11', 2400, 'Gehalt', DateTime(2026, 11, 28), income: true, note: 'Hapag-Lloyd')];
    final day = DateTime(2026, 11, 29);
    final tip = BuddyTips.pick(tx: tx, budgets: const [], now: day, hints: const [])!;
    // rent, phone and Netflix are the fixed costs; nothing to put aside yet
    expect(tip.text, 'Gehalt da: 2.400,00\u00a0€. 795,99\u00a0€ fix, 1.604,01\u00a0€ frei.');
    expect(tip.question, allOf(contains('2.400,00'), contains('Schlag mir vor')));
    // the same all day
    expect(BuddyTips.pick(tx: tx, budgets: const [], now: day, hints: const [])!.text, tip.text);
    // money put aside since: the plan is done
    await BuddyLog.add('save', 'Zurücklegen', '', const {}, now: day);
    expect(BuddyTips.pick(tx: tx, budgets: const [], now: day, hints: const [])?.text ?? '', isNot(contains('Gehalt da:')));
    await box.delete('buddyLog');
    // two visits later it is no news any more
    BuddyTips.pick(tx: tx, budgets: const [], now: DateTime(2026, 11, 30), hints: const []);
    expect(BuddyTips.pick(tx: tx, budgets: const [], now: DateTime(2026, 12, 1), hints: const [])?.text ?? '',
        isNot(contains('Gehalt da:')));
  });

  test('back after some days: one line on what happened since, only then', () {
    final tx = _ledger();
    // the first visit has nothing to compare with
    expect(BuddyTips.pick(tx: tx, budgets: const [], now: DateTime(2026, 11, 10), hints: const [])?.text ?? '',
        isNot(contains('Seit')));
    final tip = BuddyTips.pick(tx: tx, budgets: const [], now: now, hints: const [])!;
    // four days of groceries since Tuesday the 10th
    expect(tip.text, 'Seit Dienstag: 60,00\u00a0€ ausgegeben.');
    expect(tip.question, contains('seit Dienstag'));
    // the next day is no return after days
    expect(BuddyTips.pick(tx: tx, budgets: const [], now: DateTime(2026, 11, 15), hints: const [])?.text ?? '',
        isNot(contains('Seit')));
  });

  test('one notification per urgent find: not twice, not after "Später", not with the topic off', () async {
    final tx = _ledger();
    final all = hints(tx);
    List<({Hint hint, String payload})> out({Set<String> seen = const {}}) =>
        NotificationService.fresh(all, AheadAgent.run(tx: tx, hints: all, now: now), seen: seen, room: 9, now: now);
    final first = out();
    final warn = first.singleWhere((n) => n.hint.kind == HintKind.overdraft);
    // it opens the agent with the find's own question
    expect(warn.payload, startsWith('buddy:Mein Konto rutscht'));
    expect(first.map((n) => n.hint.id).toSet(), hasLength(first.length));
    // a price rise opens the agent too, not a list
    expect(first.singleWhere((n) => n.hint.kind == HintKind.priceUp).payload, startsWith('buddy:'));
    // the quiet rule still holds: one a day
    expect(NotificationService.fresh(all, AheadAgent.run(tx: tx, hints: all, now: now), seen: const {}, room: 1, now: now).single.hint.id,
        warn.hint.id);
    expect(out(seen: {warn.hint.id}).any((n) => n.hint.id == warn.hint.id), isFalse);

    await box.put('notify_spending', false);
    expect(out().any((n) => n.hint.kind == HintKind.overdraft), isFalse);
    await box.delete('notify_spending');

    await AheadAgent.snooze(warn.hint.id, now: now);
    expect(out().any((n) => n.hint.kind == HintKind.overdraft), isFalse);
  });
}
