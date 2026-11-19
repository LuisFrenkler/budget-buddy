// Two early warnings: the account runs into the overdraft before payday, and
// a direct debit that came back while the bill is still open.
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_markers.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/hints_service.dart';
import 'package:budget_buddy/services/oddities.dart';
import 'package:budget_buddy/services/overdraft.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String id, double eur, String category, DateTime date,
        {bool income = false, String? note, String? raw}) =>
    Transaction(
        id: id,
        amountCents: (eur * 100).round(),
        category: category,
        date: date,
        isIncome: income,
        note: note,
        raw: raw);

// salary on the 28th, rent on the 1st, phone on the 20th, 15 € a day of groceries
List<Transaction> _data() => [
      for (final m in [8, 9, 10]) ...[
        _t('g$m', 2400, 'Gehalt', DateTime(2026, m, 28), income: true, note: 'Hapag-Lloyd'),
        _t('m$m', 750, 'Wohnen', DateTime(2026, m, 1), note: 'Miete'),
        _t('h$m', 30, 'Sonstiges', DateTime(2026, m, 20), note: 'Telekom'),
      ],
      _t('m11', 750, 'Wohnen', DateTime(2026, 11, 1), note: 'Miete'),
      for (var d = 0; d < 90; d++) _t('l$d', 15, 'Lebensmittel', DateTime(2026, 11, 14).subtract(Duration(days: d + 1)), note: 'Rewe'),
    ];

void main() {
  final now = DateTime(2026, 11, 14);

  group('overdraft before payday', () {
    test('the next payday comes from the usual salary day', () {
      expect(Overdraft.nextPayday(_data(), now), DateTime(2026, 11, 28));
      expect(Overdraft.nextPayday(_data(), DateTime(2026, 10, 29)), DateTime(2026, 11, 28));
      // no salary for weeks: no guess
      expect(Overdraft.nextPayday(_data(), DateTime(2027, 1, 20)), isNull);
    });

    test('balance minus what is due minus ordinary days below zero: a warning', () {
      // 14 days to payday: Telekom 30 € on the 20th, 15 € a day = 210 €
      final r = Overdraft.check(_data(), balanceCents: 20000, now: now)!;
      expect(r.payday, DateTime(2026, 11, 28));
      expect(r.dueNames, ['Telekom']);
      expect(r.dueCents, 3000);
      expect(r.dailyCents, 1500);
      expect(r.shortCents, 3000 + 21000 - 20000);
      expect(Overdraft.check(_data(), balanceCents: 30000, now: now), isNull);
    });

    test('the hint comes first and asks Buddy for a way through', () {
      final hints = HintsService.build(tx: _data(), budgets: const [], goals: const [], balanceCents: 20000, now: now);
      final h = hints.firstWhere((h) => h.kind == HintKind.overdraft);
      expect(h.urgent, isTrue);
      expect(h.title, contains('40,00'));
      expect(h.text, contains('Telekom'));
      expect(h.question, contains('ohne Dispo'));
      expect(HintsService.build(tx: _data(), budgets: const [], goals: const [], now: now)
          .where((h) => h.kind == HintKind.overdraft), isEmpty);
    });

    test('the forecast tool carries the risk for the agent', () {
      final tools = BuddyTools(tx: _data(), snapshot: {'kontostand': 200.0}, now: now);
      final r = tools.run('monatsprognose', {});
      expect(r['minusVorDemGehalt']['fehltVoraussichtlich'], 40.0);
      expect(r['minusVorDemGehalt']['gehaltErwartet'], '2026-11-28');
    });
  });

  group('returned direct debits', () {
    final debit = _t('d', 89.90, 'Sonstiges', DateTime(2026, 11, 3),
        note: 'Vodafone', raw: 'Vodafone GmbH SEPA-Lastschrift Mandatsref. VF-123');

    test('the bank says Rücklastschrift', () {
      final back = _t('b', 89.90, 'Sonstiges', DateTime(2026, 11, 6),
          income: true, note: 'Vodafone', raw: 'Rücklastschrift Vodafone GmbH mangels Deckung');
      final r = Oddities.returnedDebits([debit, back], now: now).single;
      expect(r.merchant, 'Vodafone');
      expect(r.debit, debit);
    });

    test('an exact reversal of a SEPA debit counts, a refund does not', () {
      final back = _t('b', 89.90, 'Sonstiges', DateTime(2026, 11, 6), income: true, note: 'Vodafone GmbH');
      expect(Oddities.returnedDebits([debit, back], now: now), hasLength(1));
      final refund = _t('r', 89.90, 'Sonstiges', DateTime(2026, 11, 6),
          income: true, note: 'Vodafone', raw: 'Gutschrift Erstattung Vodafone');
      expect(Oddities.returnedDebits([debit, refund], now: now), isEmpty);
      // a card purchase that came back is a return, not a returned debit
      final card = _t('c', 49, 'Kleidung', DateTime(2026, 11, 2), note: 'Zalando', raw: 'Kartenzahlung Zalando');
      final cardBack = _t('cb', 49, 'Kleidung', DateTime(2026, 11, 8), income: true, note: 'Zalando');
      expect(Oddities.returnedDebits([card, cardBack], now: now), isEmpty);
    });

    test('older than two weeks: no more hint', () {
      final back = _t('b', 89.90, 'Sonstiges', DateTime(2026, 10, 20), income: true, raw: 'Rücklastschrift Vodafone');
      expect(Oddities.returnedDebits([back], now: now), isEmpty);
    });

    test('the hint and the tool', () {
      final back = _t('b', 89.90, 'Sonstiges', DateTime(2026, 11, 6), income: true, note: 'Vodafone', raw: 'Rücklastschrift');
      final h = HintsService.build(tx: [debit, back], budgets: const [], goals: const [], now: now)
          .firstWhere((h) => h.kind == HintKind.returnedDebit);
      expect(h.title, 'Lastschrift von Vodafone ging zurück');
      expect(h.question, contains('89,90'));
      final r = BuddyTools(tx: [debit, back], snapshot: const {}, now: now).run('auffaelligkeiten', {});
      expect((r['zurueckgegangeneLastschriften'] as List).single['haendler'], 'Vodafone');
    });
  });

  test('a question back can come with up to four answers to tap', () {
    final m = BuddyMarkers.parse('Welche Steuerklasse?\n[weiter: Klasse I | Klasse III | Klasse IV | Weiß nicht]');
    expect(m.followUps, hasLength(4));
  });
}
