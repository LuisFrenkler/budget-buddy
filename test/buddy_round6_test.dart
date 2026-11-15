// Reminder fees and debt collectors, and charts and cards a screen reader
// can follow.
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/booking_text.dart';
import 'package:budget_buddy/services/buddy_proposals.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/hints_service.dart';
import 'package:budget_buddy/services/oddities.dart';
import 'package:budget_buddy/widgets/buddy_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String id, double eur, DateTime d, {String? note, String? raw, bool income = false}) => Transaction(
    id: id, amountCents: (eur * 100).round(), category: 'Sonstiges', date: d, isIncome: income, note: note, raw: raw);

void main() {
  final now = DateTime(2026, 11, 14);

  group('reminder fees and debt collectors', () {
    final fee = _t('f', 5, DateTime(2026, 11, 10), note: 'Vodafone', raw: 'Vodafone Mahngebühr Rechnung 4711');
    final collector = _t('i', 87.40, DateTime(2026, 11, 12), note: 'Riverty', raw: 'Riverty GmbH Forderung Klarna');

    test('found from the bank text, collectors marked', () {
      final d = Oddities.dunning([fee, collector, _t('x', 30, DateTime(2026, 11, 1), note: 'Rewe')], now: now);
      expect(d.map((x) => x.tx.id), ['i', 'f']);
      expect(d.first.collector, isTrue);
      expect(d.last.collector, isFalse);
      // a month and more ago: no longer news
      expect(Oddities.dunning([_t('o', 5, DateTime(2026, 9, 1), raw: 'Mahngebühr')], now: now), isEmpty);
    });

    test('a collector is an urgent hint, a reminder fee a calm one', () {
      final h = HintsService.build(tx: [fee, collector], budgets: const [], goals: const [], now: now)
          .firstWhere((h) => h.kind == HintKind.dunning);
      expect(h.title, 'Zahlung an ein Inkassobüro');
      expect(h.urgent, isTrue);
      expect(h.text, contains('Verbraucherzentrale'));
      final calm = HintsService.build(tx: [fee], budgets: const [], goals: const [], now: now)
          .firstWhere((h) => h.kind == HintKind.dunning);
      expect(calm.title, 'Mahngebühr bei Vodafone');
      expect(calm.urgent, isFalse);
    });

    test('the tool and the booking explanation know them', () {
      final r = BuddyTools(tx: [fee, collector], snapshot: const {}, now: now).run('auffaelligkeiten', {});
      expect((r['mahnungenUndInkasso'] as List).first['inkasso'], isTrue);
      expect(BookingText.explain(raw: fee.raw, note: fee.note, income: false).first, contains('zu spät'));
      expect(BookingText.explain(raw: collector.raw, note: collector.note, income: false).first, contains('Inkassobüro'));
    });
  });

  testWidgets('a chart reads as one sentence, a card says what its buttons do', (tester) async {
    final handle = tester.ensureSemantics();
    const chart = BuddyChart(ChartKind.categories, 'Ausgaben nach Kategorie', [
      (label: 'Wohnen', a: 70000, b: 0),
      (label: 'Lebensmittel', a: 32000, b: 0),
    ]);
    expect(BuddyChartCard.describe(chart), startsWith('Diagramm Ausgaben nach Kategorie: Wohnen 700,00'));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BuddyChartCard(chart))));
    expect(find.bySemanticsLabel(RegExp(r'^Diagramm Ausgaben nach Kategorie: Wohnen')), findsOneWidget);
    const plan = BuddyChart(ChartKind.plan, 'Sparplan', [(label: 'Dez', a: 20000, b: 60000), (label: 'Jan', a: 40000, b: 60000)]);
    expect(BuddyChartCard.describe(plan), contains('nach 2 Monaten 400,00'));
    handle.dispose();
  });
}
