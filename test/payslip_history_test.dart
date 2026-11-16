import 'dart:io';

import 'package:budget_buddy/services/buddy_proposals.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/payslip_check.dart';
import 'package:budget_buddy/services/payslip_history.dart';
import 'package:budget_buddy/widgets/buddy_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('paysliphist').path);
    await Hive.openBox('settings');
  });

  setUp(() async => Hive.box('settings').clear());

  test('chart needs two months, then brutto, netto and deductions', () async {
    expect(PayslipHistory.chart(), isNull);
    await PayslipHistory.add(const Payslip(brutto: 3100, netto: 1950, monat: '2026-09'));
    expect(PayslipHistory.chart(), isNull);
    // stored out of order; a slip without net does not count
    await PayslipHistory.add(const Payslip(brutto: 3000, monat: '2026-07'));
    await PayslipHistory.add(const Payslip(brutto: 3000, netto: 1900, monat: '2026-08'));
    final c = PayslipHistory.chart()!;
    expect(c.kind, ChartKind.payslip);
    expect(c.rows.map((r) => r.label), ['Aug', 'Sep']);
    expect(c.rows.first.a, 300000);
    expect(c.rows.first.b, 190000);
    expect(c.rows.last.b, 195000);
    // 3.000 − 1.900 = 1.100 deductions
    expect(BuddyChartCard.describe(c), contains('Abzüge'));
    expect(BuddyChartCard.describe(c), contains('1.100,00'));
  });

  test('paid-out stands in for net, a year change stays on the label', () async {
    await PayslipHistory.add(const Payslip(brutto: 3000, auszahlung: 1800, monat: '2025-12'));
    await PayslipHistory.add(const Payslip(brutto: 3000, netto: 1900, monat: '2026-01'));
    final c = PayslipHistory.chart()!;
    expect(c.rows.map((r) => r.label), ['Dez 25', 'Jan 26']);
    expect(c.rows.first.b, 180000);
  });

  test('Buddy can show the chart once two payslips are saved', () async {
    final tools = BuddyTools(tx: const [], snapshot: const {}, now: DateTime(2026, 9, 1));
    expect(tools.run('diagramm', {'art': 'abrechnung'})['fehler'], contains('Foto'));
    await PayslipHistory.add(const Payslip(brutto: 3000, netto: 1900, monat: '2026-08'));
    await PayslipHistory.add(const Payslip(brutto: 3100, netto: 1950, monat: '2026-09'));
    final r = tools.run('diagramm', {'art': 'abrechnung'});
    expect(r['diagramm'], 'gezeigt');
    expect(r['monate'], 2);
    expect(tools.charts.single.kind, ChartKind.payslip);
  });

  testWidgets('the payslip chart names all three amounts', (tester) async {
    const chart = BuddyChart(ChartKind.payslip, 'Brutto, Netto, Abzüge', [
      (label: 'Aug', a: 300000, b: 190000),
    ]);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BuddyChartCard(chart))));
    expect(find.text('Brutto'), findsOneWidget);
    expect(find.text('Netto'), findsOneWidget);
    expect(find.text('Abzüge'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'Abzüge')), findsOneWidget);
  });
}
