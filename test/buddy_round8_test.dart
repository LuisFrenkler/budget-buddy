// Buy now, pay later as a monthly sum, a follow-up a week after a card,
// and a look at the insurances by type.
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_log.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/hints_service.dart';
import 'package:budget_buddy/services/installments.dart';
import 'package:budget_buddy/services/insurance_check.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String id, double eur, DateTime d, {String? note, String? raw}) => Transaction(
    id: id, amountCents: (eur * 100).round(), category: 'Sonstiges', date: d, isIncome: false, note: note, raw: raw);

void main() {
  final now = DateTime(2026, 11, 14);

  group('instalments', () {
    final tx = [
      for (final m in [9, 10, 11]) _t('k$m', 33.30, DateTime(2026, m, 5), note: 'Zalando', raw: 'Klarna Bank AB Ratenkauf Zalando'),
      for (final m in [10, 11]) _t('p$m', 50, DateTime(2026, m, 12), note: 'PayPal', raw: 'PayPal Europe Ratenzahlung Mediamarkt'),
      // a single Klarna invoice is no instalment
      _t('one', 79, DateTime(2026, 11, 2), note: 'Klarna', raw: 'Klarna Rechnung H&M'),
      // ended months ago
      for (final m in [3, 4, 5]) _t('o$m', 20, DateTime(2026, m, 5), note: 'Klarna', raw: 'Klarna Ratenkauf Otto'),
    ];

    test('the same amount to a financing provider in two months or more', () {
      final r = Installments.detect(tx, now: now);
      expect(r, hasLength(2));
      expect(r.first.provider, 'PayPal Ratenzahlung');
      expect(r.last.shop, 'Zalando');
      expect(r.last.paidCount, 3);
      expect(Installments.monthly(r), 8330);
    });

    test('a monthly hint and the tool', () {
      final h = HintsService.build(tx: tx, budgets: const [], goals: const [], now: now)
          .firstWhere((h) => h.kind == HintKind.installments);
      expect(h.title, contains('2 Ratenzahlungen'));
      expect(h.question, contains('83,30'));
      final r = BuddyTools(tx: tx, snapshot: const {}, now: now).run('auffaelligkeiten', {});
      expect((r['ratenkaeufe'] as List).length, 2);
    });
  });

  group('a week after a card', () {
    BuddyLogEntry e(String kind, int daysAgo, {bool undone = false}) => BuddyLogEntry(
        '$kind$daysAgo', kind, 'Budget Lebensmittel 250 €', '', now.subtract(Duration(days: daysAgo)), const {},
        undone: undone);

    test('asks seven to ten days later, once, not for undone ones', () {
      List<Hint> f(List<BuddyLogEntry> done) => HintsService.build(tx: const [], budgets: const [], goals: const [], done: done, now: now)
          .where((h) => h.kind == HintKind.followUp)
          .toList();
      expect(f([e('budget', 8)]).single.question, contains('Budget Lebensmittel'));
      expect(f([e('budget', 3)]), isEmpty);
      expect(f([e('budget', 12)]), isEmpty);
      expect(f([e('budget', 8, undone: true)]), isEmpty);
      expect(f([e('category', 8)]), isEmpty);
      expect(f([e('cancel', 7)]).single.text, contains('Bestätigung'));
    });
  });

  group('insurances by type', () {
    test('types, twice, rarely needed, liability missing', () {
      final r = InsuranceCheck.check([
        'Kfz-Haftpflicht HUK',
        'Handyversicherung Display',
        'Hausrat Allianz',
        'Hausratversicherung ARAG',
        'Deutsche Rentenversicherung',
        'Netflix',
      ]);
      expect(r.found.map((f) => f.type), ['kfz', 'handy', 'hausrat', 'hausrat']);
      expect(r.twice, ['hausrat']);
      expect(r.rarelyNeeded, ['handy']);
      expect(r.liabilityMissing, isTrue);
      expect(InsuranceCheck.check(['Privathaftpflicht']).liabilityMissing, isFalse);
    });

    test('the tool reads contracts and the wealth list', () {
      final tools = BuddyTools(tx: const [], snapshot: {
        'vertraegeUndAbos': [
          {'name': 'Haftpflicht Getsafe', 'proMonat': 5.0},
          {'name': 'Handyversicherung', 'proMonat': 9.99},
        ],
        'vermoegen': {
          'versicherungen': [
            {'name': 'BU Versicherung', 'proMonat': 60.0}
          ]
        },
      }, now: now);
      final r = tools.run('versicherungen_pruefen', {});
      expect((r['gefunden'] as List).map((x) => x['art']), containsAll(['haftpflicht', 'handy', 'bu']));
      expect(r['haftpflichtFehlt'], isFalse);
      expect(r['oftUnnoetigMitZwanzig'], ['handy']);
      expect(r['summeProMonat'], 74.99);
      expect(BuddyTools(tx: const [], snapshot: const {}, now: now).run('versicherungen_pruefen', {})['hinweis'],
          contains('Privathaftpflicht'));
    });
  });
}
