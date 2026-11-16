// Insurance check offline (LocalBuddy + wealth notes), and a yearly
// interest rate stored on each debt.
import 'package:budget_buddy/l10n/l10n.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/finance_snapshot.dart';
import 'package:budget_buddy/services/insurance_check.dart';
import 'package:budget_buddy/services/local_buddy.dart';
import 'package:budget_buddy/services/wealth.dart';
import 'package:flutter_test/flutter_test.dart';

FinanceSnapshot _snap(
        {List<Debt> debts = const [],
        List<({String name, int monthlyCents})> policies = const []}) =>
    FinanceSnapshot.build(
      tx: const [],
      openingCents: 0,
      budgets: const [],
      holdings: const [],
      now: DateTime(2026, 11, 15),
      debts: debts,
      policies: policies,
    );

void main() {
  setUp(() => L10n.lang.value = 'de');
  tearDown(() => L10n.lang.value = 'de');

  group('insurance check offline', () {
    test('notes: liability missing, twice, rarely needed', () {
      final n = InsuranceCheck.notes(InsuranceCheck.check(
          ['Handyversicherung', 'Hausrat A', 'Hausrat B']));
      expect(n.join('\n'), contains('Privathaftpflicht fehlt'));
      expect(n.join('\n'), contains('Hausrat mehr als einmal'));
      expect(n.join('\n'), contains('Handyversicherung lohnt'));
    });

    test('LocalBuddy answers without the AI', () {
      final a = LocalBuddy.answer(
          'Bin ich überversichert?',
          _snap(policies: [
            (name: 'Handyversicherung Display', monthlyCents: 999)
          ]));
      expect(a, startsWith('**9,99'));
      expect(a, contains('Privathaftpflicht fehlt'));
      expect(a, contains('Handyversicherung'));
      expect(a, isNot(contains('Versicherungs-Check')));
    });

    test('empty inventory points at liability', () {
      expect(LocalBuddy.answer('Welche Versicherungen habe ich?', _snap()),
          contains('Privathaftpflicht'));
    });

    test('liability present is a calm line', () {
      final r = InsuranceCheck.check(['Privathaftpflicht Getsafe']);
      expect(r.liabilityMissing, isFalse);
      expect(InsuranceCheck.notes(r), isEmpty);
    });
  });

  group('interest on a debt', () {
    test('round-trip, label, parse', () {
      final d = Debt.fromMap(
          {'id': '1', 'name': 'Karte', 'cents': 120000, 'ratePercent': 18});
      expect(d.ratePercent, 18);
      expect(d.toMap()['ratePercent'], 18);
      expect(d.rateLabel, '18 % Zins');
      expect(Debt.parseRate('12,5 %'), 12.5);
      expect(Debt.parseRate(''), isNull);
      expect(Debt.parseRate('-1'), isNull);
      expect(Debt.fromMap({'id': '2', 'name': 'Alt', 'cents': 1}).ratePercent,
          isNull);
    });

    test('the plan uses the stored rate', () {
      final r = BuddyTools(tx: const [], snapshot: {
        'vermoegen': {
          'schulden': [
            {'name': 'Kreditkarte', 'betrag': 1200.0, 'zins': 18},
            {'name': 'Dispo', 'betrag': 600.0, 'zins': 12.5},
          ]
        }
      }, now: DateTime(2026, 11, 15))
          .run('schulden_plan', {'extraProMonat': 300});
      expect((r['reihenfolge'] as List).first['name'], 'Kreditkarte');
      expect(r.containsKey('ohneZinssatz'), isFalse);
    });

    test('snapshot JSON and LocalBuddy show the rate', () {
      final s = _snap(debts: [
        const Debt(id: '1', name: 'Karte', cents: 120000, ratePercent: 18)
      ]);
      expect(s.toJson()['vermoegen']['schulden'][0]['zins'], 18);
      expect(LocalBuddy.answer('Wie ist mein Vermögen?', s),
          contains('18 % Zins'));
    });
  });
}
