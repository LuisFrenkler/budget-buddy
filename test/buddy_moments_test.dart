import 'package:budget_buddy/models/budget.dart';
import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/hints_service.dart';
import 'package:budget_buddy/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 14, 10);

  test('the salary that just arrived is a moment to put some aside', () {
    final hints = HintsService.build(
      tx: [
        Transaction(
            id: 's', amountCents: 235000, category: 'Gehalt', date: DateTime(2026, 11, 13), isIncome: true, note: 'Gehalt'),
        // last month's salary is old news
        Transaction(
            id: 'o', amountCents: 235000, category: 'Gehalt', date: DateTime(2026, 10, 28), isIncome: true, note: 'Gehalt'),
      ],
      budgets: const [],
      goals: const [],
      now: now,
    );
    final salary = hints.where((h) => h.kind == HintKind.salaryIn).toList();
    expect(salary.length, 1);
    expect(salary.single.text, contains('2.350,00'));
    expect(salary.single.question, contains('zur Seite'));
  });

  test('the first days of a month: close the last one with Buddy', () {
    final october = [
      for (var d = 1; d <= 12; d++)
        Transaction(id: 'o$d', amountCents: 1500, category: 'Lebensmittel', date: DateTime(2026, 10, d * 2), isIncome: false)
    ];
    final early = HintsService.build(tx: october, budgets: const [], goals: const [], now: DateTime(2026, 11, 2));
    final review = early.where((h) => h.kind == HintKind.monthReview).single;
    expect(review.question, contains('Oktober'));
    expect(review.question, contains('November'));
    expect(review.target, HintTarget.buddy);
    // later in the month, or with too little last month, there is none
    expect(HintsService.build(tx: october, budgets: const [], goals: const [], now: now)
        .where((h) => h.kind == HintKind.monthReview), isEmpty);
    expect(HintsService.build(tx: october.take(3).toList(), budgets: const [], goals: const [], now: DateTime(2026, 11, 2))
        .where((h) => h.kind == HintKind.monthReview), isEmpty);
  });

  test('a month that will not work out is urgent and leads to Buddy', () {
    final hints = HintsService.build(tx: const [], budgets: const [], goals: const [], freeCents: -12000, now: now);
    final low = hints.single;
    expect(low.kind, HintKind.lowMonth);
    expect(low.urgent, isTrue);
    expect(low.text, contains('120,00'));
    expect(low.target, HintTarget.buddy);
    expect(HintsService.build(tx: const [], budgets: const [], goals: const [], freeCents: 5000, now: now), isEmpty);
  });

  test('a reached goal asks what comes next', () {
    final hints = HintsService.build(
      tx: const [],
      budgets: const [],
      goals: [
        Goal(id: 'u', name: 'Urlaub', emoji: '✈️', targetCents: 80000, savedCents: 80000, createdAt: DateTime(2026, 5)),
      ],
      now: now,
    );
    expect(hints.single.kind, HintKind.goalReached);
    expect(hints.single.question, contains('nächstes Ziel'));
  });

  test('a budget warns at 80 percent', () {
    final hints = HintsService.build(
      tx: const [],
      budgets: [
        Budget(
            category: 'Lebensmittel',
            limitCents: 25000,
            spentCents: 20500,
            startDate: DateTime(2026, 11, 1),
            endDate: DateTime(2026, 11, 30)),
      ],
      goals: const [],
      now: now,
    );
    expect(hints.single.kind, HintKind.budgetClose);
    expect(hints.single.question, contains('Lebensmittel'));
  });

  test('a reminder Buddy was asked for arrives in the morning and opens his chat', () {
    final plan = NotificationService.plan(
      tx: const [],
      goals: const [],
      tasks: [
        (text: 'Personalabteilung fragen', due: DateTime(2026, 11, 20)),
        (text: 'Schon vorbei', due: DateTime(2026, 11, 1)),
      ],
      now: now,
    );
    final task = plan.where((r) => r.title == 'Erinnerung von Buddy').toList();
    expect(task.length, 1);
    expect(task.single.when, DateTime(2026, 11, 20, 9));
    expect(task.single.payload, 'buddy:Hilf mir bei diesem Schritt: Personalabteilung fragen');
  });

  test('every topic has a name, a description and an icon in the settings', () {
    for (final t in NotifyTopic.values) {
      expect(t.label, isNotEmpty);
      expect(t.description, isNotEmpty);
    }
  });
}
