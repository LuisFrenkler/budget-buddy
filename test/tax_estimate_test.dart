import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/net_salary.dart';
import 'package:budget_buddy/services/tax_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a full year without extra costs: nothing comes back', () {
    final r = TaxEstimate.compute(const TaxProfile(grossMonth: 3000));
    // 16 € account fee alone stays under the 1,230 € allowance
    expect(r.refund, closeTo(0, 0.5));
    expect(r.notes.join(), contains('Pauschbetrag'));
  });

  test('commute 2026: 0.38 € from the first km', () {
    // 25 km, five office days, a full year: 220 days × 25 × 0.38 = 2,090 €
    final r = TaxEstimate.compute(const TaxProfile(grossMonth: 3000, km: 25));
    expect(r.commute, closeTo(2090, 0.01));
    expect(r.aboveAllowance, closeTo(2090 + 16 - 1230, 0.01));
    // the extra 876 € lower the taxable income at about 24 % at this pay
    expect(r.refund, inInclusiveRange(180, 260));
  });

  test('home office: 6 € a day, at most 210 days', () {
    final r = TaxEstimate.compute(const TaxProfile(grossMonth: 3000, officeDaysPerWeek: 2, homeDaysPerWeek: 3));
    expect(r.homeOffice, 132 * 6.0);
    final all = TaxEstimate.compute(const TaxProfile(grossMonth: 3000, officeDaysPerWeek: 0, homeDaysPerWeek: 5));
    expect(all.homeOffice, 210 * 6.0);
  });

  test('a first job from September: most of the wage tax comes back', () {
    final r = TaxEstimate.compute(const TaxProfile(grossMonth: 3500, monthsWorked: 4));
    final monthly = NetSalary.compute(3500).wageTax;
    expect(r.withheld, closeTo(monthly * 4, 1));
    // 14,000 € in the year: the taxable income ends up near the basic allowance
    expect(r.due, lessThan(200));
    expect(r.refund, greaterThan(1300));
    expect(r.notes.join(), contains('4 Monate'));
  });

  test('bookings that may count are found by what they are', () {
    final tx = [
      Transaction(id: 'a', amountCents: 4990, category: 'Bildung', date: DateTime(2026, 3, 2), isIncome: false, note: 'Udemy'),
      Transaction(id: 'b', amountCents: 1600, category: 'Sonstiges', date: DateTime(2026, 4, 1), isIncome: false, note: 'ver.di Beitrag'),
      Transaction(id: 'c', amountCents: 39900, category: 'Wohnen', date: DateTime(2026, 9, 1), isIncome: false, note: 'Umzugsunternehmen Meier'),
      Transaction(id: 'd', amountCents: 899, category: 'Lebensmittel', date: DateTime(2026, 9, 2), isIncome: false, note: 'Rewe'),
      Transaction(id: 'e', amountCents: 4990, category: 'Bildung', date: DateTime(2025, 3, 2), isIncome: false, note: 'Udemy'),
    ];
    final c = TaxEstimate.candidates(tx, 2026);
    expect({for (final x in c) x.tx.id: x.kind}, {'a': 'fortbildung', 'b': 'gewerkschaft', 'c': 'umzug'});
  });
}
