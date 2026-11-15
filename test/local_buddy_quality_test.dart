// Offline answers open on the figure: a bold amount, or the affordability light.
// A label, a list, or a second essay must not come first.
import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/finance_snapshot.dart';
import 'package:budget_buddy/services/local_buddy.dart';
import 'package:budget_buddy/services/wealth.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String note, String cat, int cents, DateTime d,
        {bool income = false}) =>
    Transaction(
        id: '$note$d$cents',
        amountCents: cents,
        category: cat,
        date: d,
        isIncome: income,
        note: note);

final _leads = RegExp(r'^(?:🟢|🟡|🔴) |\*\*(?:€\s?)?[−-]?\d');

void main() {
  final now = DateTime(2026, 10, 20);
  final tx = [
    for (int m = 7; m <= 10; m++) ...[
      _t('Gehalt', 'Gehalt', 300000, DateTime(2026, m, 1), income: true),
      _t('Miete', 'Wohnen', 90000, DateTime(2026, m, 3)),
      _t('Netflix', 'Unterhaltung', 1399, DateTime(2026, m, 12)),
      _t('REWE', 'Lebensmittel', m == 10 ? 60000 : 30000, DateTime(2026, m, 15)),
    ],
  ];
  final goal = Goal(
    id: 'g1',
    name: 'Urlaub',
    emoji: '🏖️',
    targetCents: 80000,
    savedCents: 20000,
    createdAt: DateTime(2026, 1, 1),
  );
  final s = FinanceSnapshot.build(
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
    recurring: [
      (
        title: 'Miete',
        cents: 90000,
        income: false,
        category: 'Wohnen',
        interval: 'monatlich',
        active: true,
        next: '2026-11-03',
      ),
    ],
  );

  test('a goal and a split open on the bold amount', () {
    final goals = LocalBuddy.answer('Wie stehen meine Sparziele?', s);
    expect(goals, startsWith('**600,00'));
    expect(goals, contains('Urlaub'));
    expect(goals, isNot(contains('🏖️')));
    expect(goals, isNot(contains('\n')));
    expect(goals.split(RegExp(r'\s+')).length, lessThan(25));

    final owed = LocalBuddy.answer('Wer schuldet mir was?', s);
    expect(owed, startsWith('**25,00'));
    expect(owed, contains('WG'));
    expect(owed, isNot(contains('\n')));
  });

  test('insurance and recurring open on the monthly amount', () {
    final ins = FinanceSnapshot.build(
      tx: tx,
      openingCents: 100000,
      budgets: const [],
      holdings: const [],
      now: now,
      policies: [(name: 'Handyversicherung Display', monthlyCents: 999)],
    );
    final a = LocalBuddy.answer('Bin ich überversichert?', ins);
    expect(a, startsWith('**9,99'));
    expect(a, contains('Privathaftpflicht'));
    expect(a, isNot(contains('Versicherungs-Check')));

    final rec = LocalBuddy.answer('Was sind meine wiederkehrenden Buchungen?', s);
    expect(rec, startsWith('**900,00'));
    expect(rec, isNot(contains('\n')));
  });

  test('accounts and wealth stay one figure, then one fact', () {
    final accounts = LocalBuddy.answer('Welche Konten habe ich?', s);
    expect(accounts, matches(_leads));
    expect(accounts, contains('Zuletzt'));
    expect(accounts, isNot(contains('Letzte Buchungen')));
    expect(accounts, isNot(contains('\n')));

    final rich = FinanceSnapshot.build(
      tx: const [],
      openingCents: 0,
      budgets: const [],
      holdings: const [],
      now: now,
      debts: [
        const Debt(id: '1', name: 'Karte', cents: 120000, ratePercent: 18)
      ],
      policies: [(name: 'Hausrat', monthlyCents: 800)],
      emergencyTargetCents: 300000,
      emergencyHaveCents: 50000,
    );
    final net = LocalBuddy.answer('Wie ist mein Vermögen?', rich);
    expect(net, matches(_leads));
    expect(net, contains('Notgroschen'));
    expect(net, contains('2.500,00'));
    expect(net, isNot(contains('Hausrat')));
    expect(net, isNot(contains('Karte')));
    expect(net.split(RegExp(r'\s+')).length, lessThan(16));

    final debt = LocalBuddy.answer('Wie stehen meine Schulden?', rich);
    expect(debt, matches(_leads));
    expect(debt, contains('18 % Zins'));
    expect(debt, contains('Karte'));
    expect(debt, isNot(contains('Hausrat')));
  });

  test('saving tips stay two lines, and the month opens on the free amount', () {
    final save = LocalBuddy.answer('Wo kann ich sparen?', s);
    expect(save, matches(_leads));
    expect(save.split('\n').length, lessThanOrEqualTo(2));
    expect(save, contains('Lebensmittel'));
    expect(save, contains('Netflix'));
    expect(save, isNot(contains('günstiger')));
    expect(save, isNot(contains('Werbung')));

    final free = LocalBuddy.answer('Wie viel bleibt bis Monatsende?', s);
    expect(free, matches(_leads));
    expect(free, contains('Monatsende'));
    expect(free.split('\n').length, 1);

    final plus = FinanceSnapshot.build(
      tx: tx,
      openingCents: 100000,
      budgets: const [],
      holdings: const [],
      now: now,
      plus: (
        active: false,
        plan: null,
        trial: false,
        cancelled: false,
        bis: null,
        fragenRest: 4,
        scansRest: 1,
      ),
    );
    expect(LocalBuddy.answer('Habe ich Plus?', plus), startsWith('**4**'));
  });
}
