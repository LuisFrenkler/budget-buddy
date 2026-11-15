// Income that is late this month, the morning warning before the overdraft,
// and the per-tool report.
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/hints_service.dart';
import 'package:budget_buddy/services/income_sources.dart';
import 'package:budget_buddy/services/notification_service.dart';
import 'package:budget_buddy/services/overdraft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/buddy_eval/tool_report.dart';

Transaction _t(String id, double eur, String category, DateTime date, {bool income = false, String? note}) =>
    Transaction(id: id, amountCents: (eur * 100).round(), category: category, date: date, isIncome: income, note: note);

void main() {
  // salary on the 1st, Kindergeld on the 10th, Aug to Oct
  List<Transaction> data({bool kindergeldNow = false, bool salaryNow = true}) => [
        for (final m in [8, 9, 10]) ...[
          _t('g$m', 1800, 'Gehalt', DateTime(2026, m, 1), income: true, note: 'Firma'),
          _t('k$m', 255, 'Sonstiges', DateTime(2026, m, 10), income: true, note: 'Familienkasse Kindergeld'),
        ],
        if (salaryNow) _t('g11', 1800, 'Gehalt', DateTime(2026, 11, 1), income: true, note: 'Firma'),
        if (kindergeldNow) _t('k11', 255, 'Sonstiges', DateTime(2026, 11, 10), income: true, note: 'Familienkasse Kindergeld'),
      ];

  test('regular income knows its usual day', () {
    final s = IncomeSources.detect(data(), now: DateTime(2026, 11, 20));
    expect(s.firstWhere((x) => x.kind == 'kindergeld').day, 10);
    expect(s.firstWhere((x) => x.kind == 'gehalt').day, 1);
  });

  test('late by more than four days: missing, before that: not yet', () {
    expect(IncomeSources.missing(data(), now: DateTime(2026, 11, 13)), isEmpty);
    expect(IncomeSources.missing(data(), now: DateTime(2026, 11, 15)).single.kind, 'kindergeld');
    expect(IncomeSources.missing(data(kindergeldNow: true), now: DateTime(2026, 11, 15)), isEmpty);
    // a salary that came on the 31st of the month before counts for this one
    final early = [
      ...data(salaryNow: false),
      _t('g10b', 1800, 'Gehalt', DateTime(2026, 10, 30), income: true, note: 'Firma'),
    ];
    expect(IncomeSources.missing(early, now: DateTime(2026, 11, 6)).where((x) => x.kind == 'gehalt'), isEmpty);
  });

  test('a missing salary is an urgent hint, Kindergeld a calm one', () {
    final now = DateTime(2026, 11, 15);
    final kg = HintsService.build(tx: data(), budgets: const [], goals: const [], now: now)
        .firstWhere((h) => h.kind == HintKind.incomeMissing);
    expect(kg.title, contains('Kindergeld'));
    expect(kg.urgent, isFalse);
    final salary = HintsService.build(tx: data(salaryNow: false, kindergeldNow: true), budgets: const [], goals: const [], now: now)
        .firstWhere((h) => h.kind == HintKind.incomeMissing);
    expect(salary.title, 'Dein Gehalt ist noch nicht da');
    expect(salary.urgent, isTrue);
    final r = BuddyTools(tx: data(), snapshot: const {}, now: now).run('monatsprognose', {});
    expect((r['ausstehendeEinnahmen'] as List).single['sonstUm'], 10);
  });

  group('morning warning before the overdraft', () {
    // salary on the 28th, rent of 700 on the 20th, 10 € a day
    final tx = [
      for (final m in [8, 9, 10]) ...[
        _t('g$m', 2000, 'Gehalt', DateTime(2026, m, 28), income: true, note: 'Firma'),
        _t('r$m', 700, 'Wohnen', DateTime(2026, m, 20), note: 'Miete'),
      ],
      for (var d = 1; d <= 90; d++) _t('e$d', 10, 'Lebensmittel', DateTime(2026, 11, 18).subtract(Duration(days: d)), note: 'Rewe'),
    ];
    final now = DateTime(2026, 11, 18, 19);

    test('the day the rent no longer fits', () {
      expect(Overdraft.firstNegativeDay(tx, balanceCents: 60000, now: now), DateTime(2026, 11, 20));
      expect(Overdraft.firstNegativeDay(tx, balanceCents: 200000, now: now), isNull);
    });

    test('a reminder at 8 that morning, opening Buddy', () {
      final plan = NotificationService.plan(tx: tx, goals: const [], balanceCents: 60000, now: now);
      final r = plan.firstWhere((r) => r.title == 'Heute rutscht dein Konto ins Minus');
      expect(r.when, DateTime(2026, 11, 20, 8));
      expect(r.payload, startsWith('buddy:'));
      expect(NotificationService.plan(tx: tx, goals: const [], now: now).where((r) => r.title.contains('Minus')), isEmpty);
    });
  });

  test('tool report: slowest first, cost and steps per answer', () {
    final report = toolReport([
      {'turn': 'a', 'tools': ['ausgaben'], 'kostenUsd': 0.002},
      {'turn': 'a', 'tools': const [], 'kostenUsd': 0.003, 'bisErstesWort': 1200},
      {'turn': 'b', 'tools': ['steuer_schaetzung', 'ausgaben'], 'kostenUsd': 0.004},
      {'turn': 'b', 'tools': const [], 'kostenUsd': 0.006, 'bisErstesWort': 3400},
    ]);
    expect(report.indexOf('steuer_schaetzung'), lessThan(report.indexOf('| ausgaben')));
    expect(report, contains('| steuer_schaetzung | 1 | 0.0100 \$ | 2.0 | 3.40 s |'));
    expect(report, contains('| ausgaben | 2 | 0.0075 \$ | 2.0 | 1.20 s |'));
    expect(toolReport(const []), contains('Noch keine'));
  });
}
