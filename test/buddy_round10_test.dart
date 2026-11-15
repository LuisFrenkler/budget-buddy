// Payslips compared month to month, and a plan to pay debts off.
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/debt_plan.dart';
import 'package:budget_buddy/services/payslip_check.dart';
import 'package:budget_buddy/services/payslip_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('payslip changes', () {
    const before = Payslip(brutto: 3000, auszahlung: 2050, steuerklasse: 1, kirche: false, zusatz: 2.9, monat: '2026-09');

    test('nothing changed: nothing to say', () {
      expect(PayslipHistory.changes(before, before), isEmpty);
    });

    test('tax class, church tax, health insurance, company pension', () {
      const now = Payslip(
          brutto: 3000, auszahlung: 1950, steuerklasse: 4, kirche: true, kirchensteuer: 21.5, zusatz: 3.4, bav: 100,
          monat: '2026-10');
      final c = PayslipHistory.changes(before, now);
      expect(c[0], contains('von 1 auf 4'));
      expect(c[1], contains('Kirchensteuer'));
      expect(c[2], contains('2,90 % auf 3,40 %'));
      expect(c[3], contains('Betriebsrente'));
      // same gross, 100 € less paid out
      expect(c.last, contains('100,00'));
    });

    test('a raise and a drop in gross', () {
      expect(PayslipHistory.changes(before, const Payslip(brutto: 3150)).single, contains('150,00'));
      expect(PayslipHistory.changes(before, const Payslip(brutto: 2600)).single, contains('weniger'));
    });
  });

  group('debt plan', () {
    test('the most expensive interest first, unknown rates smallest first', () {
      final order = DebtPlan.sorted(const [
        DebtItem('Kredit', 500000, ratePercent: 6),
        DebtItem('Freund', 30000),
        DebtItem('Kreditkarte', 120000, ratePercent: 18),
        DebtItem('Eltern', 100000),
      ]);
      expect(order.map((d) => d.name), ['Kreditkarte', 'Kredit', 'Freund', 'Eltern']);
    });

    test('rates roll over: one at a time, all gone, interest counted', () {
      final r = DebtPlan.compute(const [
        DebtItem('Kreditkarte', 120000, ratePercent: 18, minCents: 5000),
        DebtItem('Dispo', 60000, ratePercent: 12, minCents: 0),
      ], extraCents: 25000);
      expect(r.order.map((s) => s.name), ['Kreditkarte', 'Dispo']);
      // 300 € a month for 1,800 €: about seven months
      expect(r.months, inInclusiveRange(6, 8));
      expect(r.interestCents, greaterThan(0));
      expect(r.tooSlow, isFalse);
    });

    test('too little to beat the interest', () {
      final r = DebtPlan.compute(const [DebtItem('Kredit', 1000000, ratePercent: 20, minCents: 10000)]);
      expect(r.tooSlow, isTrue);
    });

    test('the tool uses the stored debts and the rates the person names', () {
      final tools = BuddyTools(tx: const [], snapshot: {
        'vermoegen': {
          'schulden': [
            {'name': 'Kreditkarte', 'betrag': 1200.0},
            {'name': 'Dispo', 'betrag': 600.0},
          ]
        }
      }, now: DateTime(2026, 11, 15));
      final r = tools.run('schulden_plan', {
        'extraProMonat': 300,
        'zinsen': {'kreditkarte': 18, 'Dispo': 12.5}
      });
      expect((r['reihenfolge'] as List).first['name'], 'Kreditkarte');
      expect(r['monateBisSchuldenfrei'], inInclusiveRange(6, 8));
      expect(r.containsKey('ohneZinssatz'), isFalse);
      final none = BuddyTools(tx: const [], snapshot: const {}, now: DateTime(2026, 11, 15)).run('schulden_plan', {});
      expect(none['hinweis'], contains('Zinssatz'));
    });
  });
}
