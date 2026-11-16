// Regular income in the forecast, cheaper plans of the same subscription,
// and the feedback report.
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/forecast_service.dart';
import 'package:budget_buddy/services/income_sources.dart';
import 'package:budget_buddy/services/sub_tips.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/buddy_eval/feedback_report.dart';

Transaction _t(String id, double eur, String category, DateTime date, {bool income = false, String? note}) =>
    Transaction(id: id, amountCents: (eur * 100).round(), category: category, date: date, isIncome: income, note: note);

void main() {
  final now = DateTime(2026, 11, 14);
  final tx = [
    for (final m in [8, 9, 10]) ...[
      _t('g$m', 1800, 'Gehalt', DateTime(2026, m, 28), income: true, note: 'Hapag-Lloyd'),
      _t('k$m', 255, 'Sonstiges', DateTime(2026, m, 12), income: true, note: 'Familienkasse Kindergeld'),
      // the side job pays a little differently every month
      _t('n$m', m == 9 ? 380 : 420, 'Nebenjob', DateTime(2026, m, 5), income: true, note: 'Café Rot Minijob'),
      _t('m$m', 700, 'Wohnen', DateTime(2026, m, 1), note: 'Miete'),
    ],
    // a tax refund once: not every month
    _t('st', 600, 'Sonstiges', DateTime(2026, 9, 20), income: true, note: 'Finanzamt Erstattung'),
    _t('m11', 700, 'Wohnen', DateTime(2026, 11, 1), note: 'Miete'),
  ];

  test('sources: salary, Kindergeld and side job regular, the refund a one-off', () {
    final s = IncomeSources.detect(tx, now: now);
    final byKind = {for (final x in s) x.kind: x};
    expect(byKind['gehalt']!.monthlyCents, 180000);
    expect(byKind['kindergeld']!.regular, isTrue);
    expect(byKind['kindergeld']!.monthlyCents, 25500);
    expect(byKind['nebenjob']!.monthlyCents, 42000); // middle of 380, 420, 420
    final refund = s.firstWhere((x) => x.name.contains('Finanzamt'));
    expect(refund.regular, isFalse);
    expect(IncomeSources.regularMonthly(s), 180000 + 25500 + 42000);
  });

  test('the forecast counts on regular income, not on the refund', () {
    final f = ForecastService.build(tx, now: now)!;
    expect(f.incomeCents, 180000 + 25500 + 42000);
  });

  test('two salaries in one month and none in the next still make one a month', () {
    final shifted = [
      _t('a', 2000, 'Gehalt', DateTime(2026, 8, 1), income: true, note: 'Firma'),
      _t('b', 2000, 'Gehalt', DateTime(2026, 8, 31), income: true, note: 'Firma'),
      _t('c', 2000, 'Gehalt', DateTime(2026, 10, 1), income: true, note: 'Firma'),
      _t('m', 50, 'Lebensmittel', DateTime(2026, 11, 2), note: 'Rewe'),
    ];
    expect(ForecastService.build(shifted, now: now)!.incomeCents, 200000);
  });

  test('the forecast tool lists the sources for Buddy', () {
    final r = BuddyTools(tx: tx, snapshot: const {}, now: now).run('monatsprognose', {});
    final list = r['einnahmequellen'] as List;
    expect(list.firstWhere((x) => x['art'] == 'kindergeld')['proMonat'], 255.0);
    expect(list.firstWhere((x) => x['regelmaessig'] == false)['einmalig'], 600.0);
  });

  test('cheaper plans of the same subscription, without prices', () {
    expect(SubTips.forName('Netflix')!.ways, ['werbung', 'teilen']);
    expect(SubTips.forName('PayPal *Spotify')!.text, contains('Spotify'));
    expect(SubTips.forName('Miete'), isNull);
    final tools = BuddyTools(tx: const [], snapshot: {
      'vertraegeUndAbos': [
        {'name': 'Netflix', 'proMonat': 13.99},
        {'name': 'Telekom', 'proMonat': 39.95},
      ]
    }, now: now);
    final r = tools.run('vertraege_und_abos', {});
    expect((r['spartipps'] as List).single['name'], 'Netflix');
  });

  test('feedback report: share, reasons, tools in bad answers, latest', () {
    final report = feedbackReport([
      {'at': '2026-11-01', 'rating': 'up', 'tools': ['ausgaben'], 'lang': 'de', 'question': 'a'},
      {'at': '2026-11-02', 'rating': 'down', 'reason': 'Zu lang', 'tools': ['ausgaben', 'diagramm'], 'lang': 'de', 'question': 'Wie viel für Essen?'},
      {'at': '2026-11-03', 'rating': 'down', 'reason': 'Zahl stimmt nicht', 'tools': ['diagramm'], 'lang': 'en', 'question': 'Show me a chart'},
      {'at': '2026-11-04', 'rating': 'down', 'reason': 'Zu lang', 'tools': const [], 'lang': 'de', 'question': 'Hi'},
    ]);
    expect(report, contains('4 Bewertungen: 1 gut, 3 schlecht (25 % gut)'));
    expect(report, contains('| Zu lang | 2 |'));
    expect(report, contains('| diagramm | 2 | 100 % |'));
    expect(report, contains('| ausgaben | 2 | 50 % |'));
    expect(report.indexOf('diagramm'), lessThan(report.indexOf('| ausgaben')));
    expect(report, contains('en 1 (100 % schlecht)'));
    expect(report, contains('- „Hi“ (Zu lang)'));
    expect(feedbackReport(const []), contains('Noch kein Feedback'));
  });
}
