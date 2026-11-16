// Payments that come once a year or every quarter, and what comes after a
// goal is reached.
import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/goal_next.dart';
import 'package:budget_buddy/services/hints_service.dart';
import 'package:budget_buddy/services/periodic_payments.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String id, double eur, DateTime d, String note) =>
    Transaction(id: id, amountCents: (eur * 100).round(), category: 'Sonstiges', date: d, isIncome: false, note: note);

void main() {
  final now = DateTime(2026, 11, 14);
  final tx = [
    // Rundfunkbeitrag every quarter
    _t('r1', 55.08, DateTime(2026, 5, 15), 'Rundfunk ARD ZDF'),
    _t('r2', 55.08, DateTime(2026, 8, 15), 'Rundfunk ARD ZDF'),
    // car insurance once, a known yearly kind
    _t('k1', 480, DateTime(2025, 12, 1), 'HUK Kfz-Versicherung'),
    // monthly: not periodic
    for (final m in [8, 9, 10, 11]) _t('n$m', 30, DateTime(2026, m, 3), 'Telekom'),
    // a one-off purchase: not periodic
    _t('x', 600, DateTime(2026, 9, 1), 'Mediamarkt'),
  ];

  test('quarter, year, and nothing monthly or one-off', () {
    final p = PeriodicPayments.detect(tx, now: now);
    final byEvery = {for (final x in p) x.everyMonths: x};
    expect(byEvery[3]!.next, DateTime(2026, 11, 15));
    expect(byEvery[3]!.monthlyCents, 1836);
    expect(byEvery[12]!.next, DateTime(2026, 12, 1));
    expect(byEvery[12]!.monthlyCents, 4000);
    expect(p, hasLength(2));
  });

  test('a big one within a month becomes a hint with the monthly amount', () {
    final h = HintsService.build(tx: tx, budgets: const [], goals: const [], now: now)
        .firstWhere((h) => h.kind == HintKind.periodicDue);
    expect(h.title, contains('480,00'));
    expect(h.text, contains('40,00'));
  });

  test('the tool lists them and offers a reserve goal once', () {
    final tools = BuddyTools(tx: tx, snapshot: const {'sparziele': []}, now: now);
    final r = tools.run('jahreszahlungen', {});
    expect((r['gefunden'] as List), hasLength(2));
    expect(r['zusammenProMonat'], 58.36);
    expect(tools.proposals.single.title, 'Sparziel Rücklage Jahreszahlungen');
    final withGoal = BuddyTools(tx: tx, snapshot: const {
      'sparziele': [
        {'name': 'Rücklage Auto'}
      ]
    }, now: now);
    withGoal.run('jahreszahlungen', {});
    expect(withGoal.proposals, isEmpty);
  });

  group('after a goal', () {
    Goal g(String id, String name, {int saved = 0, int target = 100000, int monthly = 0, DateTime? deadline}) => Goal(
        id: id, name: name, emoji: '🎯', targetCents: target, savedCents: saved, createdAt: DateTime(2026),
        monthlyCents: monthly, deadline: deadline);

    test('the Notgroschen leads to investing', () {
      final n = GoalNext.suggest(g('a', 'Notgroschen', saved: 100000, monthly: 20000), const []);
      expect(n.text, contains('200,00'));
      expect(n.question, contains('langfristig'));
    });

    test('the rate goes on to the next open goal, the nearest deadline first', () {
      final done = g('a', 'Urlaub', saved: 100000, monthly: 15000);
      final n = GoalNext.suggest(done, [
        done,
        g('b', 'Laptop', deadline: DateTime(2027, 6)),
        g('c', 'Umzug', deadline: DateTime(2027, 2)),
        g('d', 'Alt', saved: 100000),
      ]);
      expect(n.text, contains('Umzug'));
      expect(n.question, contains('Urlaub ist geschafft'));
    });

    test('nothing open: plan the next one with Buddy', () {
      final done = g('a', 'Urlaub', saved: 100000);
      expect(GoalNext.suggest(done, [done]).question, contains('nächstes Sparziel'));
    });
  });
}
