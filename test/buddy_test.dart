import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/models/budget.dart';
import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/finance_snapshot.dart';
import 'package:budget_buddy/services/buddy_suggestions.dart';
import 'package:budget_buddy/services/local_buddy.dart';
import 'package:budget_buddy/services/vorsorge.dart';
import 'package:budget_buddy/services/wealth.dart';

Transaction _t(String note, String cat, int cents, DateTime d,
        {bool income = false}) =>
    Transaction(
        id: '$note$d$cents',
        amountCents: cents,
        category: cat,
        date: d,
        isIncome: income,
        note: note);

// offline answers open on the figure: a bold amount, or the affordability light
final _leads = RegExp(r'^(?:🟢|🟡|🔴) |\*\*(?:€\s?)?[−-]?\d');

void main() {
  final now = DateTime(2026, 10, 20);
  final tx = [
    for (int m = 7; m <= 10; m++) ...[
      _t('Gehalt', 'Gehalt', 300000, DateTime(2026, m, 1), income: true),
      _t('Miete', 'Wohnen', 90000, DateTime(2026, m, 3)),
      _t('Netflix', 'Unterhaltung', 1399, DateTime(2026, m, 12)),
      _t('REWE', 'Lebensmittel', m == 10 ? 60000 : 30000,
          DateTime(2026, m, 15)),
    ],
  ];
  final s = FinanceSnapshot.build(
      tx: tx,
      openingCents: 100000,
      budgets: const [],
      holdings: const [],
      now: now);

  test('snapshot sums months, balance and contracts', () {
    expect(s.current.expenses, 90000 + 1399 + 60000);
    expect(
        s.balanceCents,
        100000 +
            4 * 300000 -
            3 * (90000 + 1399 + 30000) -
            (90000 + 1399 + 60000));
    expect(s.contracts.map((c) => c.name), containsAll(['Miete', 'Netflix']));
    expect(s.toJson()['monate'], hasLength(6));
  });

  test('saving tips lead with a bold number', () {
    final a = LocalBuddy.answer('Wo kann ich sparen?', s);
    expect(a, matches(_leads));
    expect(a, contains('Lebensmittel'));
    expect(a, contains('Netflix'));
    expect(a, isNot(contains('Nächster Schritt')));
  });

  test('affordability leads with a traffic light and the amount', () {
    final a = LocalBuddy.answer('Kann ich mir 800 € Urlaub leisten?', s);
    // past months: 3.000 € in, 1.213,99 € out
    expect(a, matches(_leads));
    expect(a.split('\n').first, contains('800'));
    expect(a.split('\n').first, matches(RegExp(r'^(🟢|🟡|🔴)')));
    expect(a, contains('1.786,01'));
    expect(a, contains('1 Monat'));
    expect(a, isNot(contains('Vom Kontostand')));
  });

  test('month free cash leads with a bold number', () {
    final a = LocalBuddy.answer('Wie viel bleibt bis Monatsende?', s);
    expect(a, matches(_leads));
    expect(a, contains('Monatsende'));
  });

  test('lists contracts', () {
    expect(LocalBuddy.answer('Welche Abos habe ich?', s), contains('Miete'));
  });

  test('snapshot keeps goals, splits and pension out of account numbers', () {
    final goal = Goal(
      id: 'g1',
      name: 'Urlaub',
      emoji: '🏖️',
      targetCents: 80000,
      savedCents: 20000,
      createdAt: DateTime(2026, 1, 1),
    );
    final rich = FinanceSnapshot.build(
      tx: tx,
      openingCents: 100000,
      budgets: const [],
      holdings: const [],
      now: now,
      goals: [goal],
      accounts: [(name: 'Giro', art: 'Girokonto', cents: 120000)],
      splits: [
        (
          name: 'WG',
          myCents: 2500,
          salden: [(name: 'Ich', cents: 2500), (name: 'Anna', cents: -2500)],
          ausgleich: [(von: 'Anna', an: 'Ich', cents: 2500)],
        ),
      ],
      debts: [const Debt(id: 'd1', name: 'Studienkredit', cents: 50000)],
      vorsorge: Vorsorge.build(
        input:
            const VorsorgeInput(age: 35, retireAge: 67, statutoryCents: 120000),
        holdings: const [],
        goals: [goal],
      ),
    );
    final j = rich.toJson();
    expect(j['sparziele'], isNotEmpty);
    expect(j['splits'][0]['meinSaldo'], 25);
    expect(j['vermoegen']['schulden'][0]['name'], 'Studienkredit');
    expect(j['vorsorge']['eingerichtet'], isTrue);
    expect(j['konten'][0].keys, containsAll(['name', 'art', 'saldo']));
    expect(j['konten'][0].keys, isNot(contains('iban')));
    expect(s.toJson()['vorsorge']['eingerichtet'], isFalse);
    expect(LocalBuddy.answer('Wie stehen meine Sparziele?', rich),
        contains('Urlaub'));
    expect(LocalBuddy.answer('Wer schuldet mir was?', rich), contains('WG'));
    expect(LocalBuddy.answer('Wie steht die Rente?', s),
        contains('nicht eingerichtet'));
    expect(LocalBuddy.answer('Kann ich mir 800 € Urlaub leisten?', rich),
        contains('1.786,01'));
    final chips = BuddySuggestions.pick(rich);
    final texts = chips.map((c) => c.text).toList();
    // activation first: free cash / save / afford before wealth topics
    expect(texts.take(3), containsAll([
      'Wie viel ist diesen Monat noch frei?',
      'Wo kann ich sparen?',
      'Kann ich mir 800 € Urlaub leisten?',
    ]));
    expect(texts, contains('Wer schuldet mir noch Geld in WG?'));
    expect(chips.length, lessThanOrEqualTo(6));
  });

  test('a budget answer leads with the tight number', () {
    final over = Budget(
      category: 'Lebensmittel',
      limitCents: 30000,
      spentCents: 45000,
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 31),
    );
    final snap = FinanceSnapshot.build(
      tx: tx,
      openingCents: 100000,
      budgets: [over],
      holdings: const [],
      now: now,
    );
    final a = LocalBuddy.answer('Wie steht mein Budget?', snap);
    expect(a, startsWith('**150,00'));
    expect(a, endsWith('über Lebensmittel.'));
    expect(a, isNot(contains('\n')));
    expect(LocalBuddy.answer('Wie steht mein Budget?', s),
        'Noch keine Budgets. Unter Budgets im Konto anlegen.');
  });

  test('an empty ledger gets one calm line', () {
    final empty = FinanceSnapshot.build(
      tx: const [],
      openingCents: 0,
      budgets: const [],
      holdings: const [],
      now: now,
    );
    expect(LocalBuddy.answer('Hallo', empty),
        'Noch wenig Verlauf. Bank verbinden oder ein paar Ausgaben erfassen.');
  });
}
