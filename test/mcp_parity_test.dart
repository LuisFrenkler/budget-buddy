// The server's copy of the tax rules and its refund check must say exactly
// what the app says, or ChatGPT and the app would show different numbers.
import 'dart:io';

import 'package:budget_buddy/services/tax_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../backend/lib/mcp.dart';

void main() {
  test('the server copy of the tax rules is the app file', () {
    final app = File('lib/services/net_salary.dart').readAsStringSync();
    final copy = File('backend/lib/tax_rules.dart').readAsStringSync().split('\n').skip(2).join('\n');
    expect(copy, app);
  });

  test('the MCP refund check gives the app numbers', () {
    final today = DateTime(2026, 11, 17);
    for (final gross in [1800.0, 3000.0, 5200.0]) {
      for (final (start, month, km) in [(2022, 9, 0.0), (2023, 1, 18.0), (2021, 5, 35.0)]) {
        final app = TaxEstimate.quickCheck(startYear: start, startMonth: month, grossMonth: gross, km: km, today: today);
        final mcp = Mcp.check(startYear: start, startMonth: month, gross: gross, km: km, today: today);
        expect(mcp.map((y) => y['jahr']), app.map((y) => y.year));
        for (var i = 0; i < app.length; i++) {
          expect(mcp[i]['bis'] as num, closeTo(app[i].high, 0.01), reason: '$gross $start ${app[i].year}');
          expect(mcp[i]['von'] as num, closeTo(app[i].low, 0.01), reason: '$gross $start ${app[i].year} low');
        }
      }
    }
  });
}
