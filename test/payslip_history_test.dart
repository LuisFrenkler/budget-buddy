import 'dart:io';

import 'package:budget_buddy/services/payslip_check.dart';
import 'package:budget_buddy/services/payslip_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('chart needs at least two payslips with brutto and netto', () async {
    final dir = Directory.systemTemp.createTempSync('paysliphist');
    Hive.init(dir.path);
    await Hive.openBox('settings');
    expect(PayslipHistory.chart(), isNull);
    await PayslipHistory.add(const Payslip(brutto: 3000, netto: 1900, monat: '2026-08'));
    expect(PayslipHistory.chart(), isNull);
    await PayslipHistory.add(const Payslip(brutto: 3100, netto: 1950, monat: '2026-09'));
    final c = PayslipHistory.chart()!;
    expect(c.rows.length, 2);
    expect(c.rows.first.a, 300000);
    expect(c.rows.last.b, 195000);
    await Hive.box('settings').close();
    await dir.delete(recursive: true);
  });
}
