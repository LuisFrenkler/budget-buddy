import 'package:budget_buddy/services/local_buddy.dart';
import 'package:budget_buddy/services/net_salary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // monthly wage tax, class I, childless, statutory insurance, 2.9 % additional
  // contribution, no church tax: reference values computed with the BMF
  // program flow 2026 (rechnercheck.de, rechner-portal.de)
  final reference = {
    2000.0: 88.16,
    2500.0: 187.33,
    3000.0: 293.08,
    3500.0: 405.50,
    4000.0: 524.50,
    4500.0: 650.16,
    5000.0: 782.41,
    6000.0: 1074.33,
    7000.0: 1430.33,
    8000.0: 1810.33,
  };

  test('wage tax matches the official 2026 program flow', () {
    reference.forEach((gross, tax) {
      expect(NetSalary.compute(gross, age: 30).wageTax, tax, reason: '$gross €');
    });
  });

  test('the 2026 tariff zones', () {
    expect(NetSalary.tariff(12348), 0);
    expect(NetSalary.tariff(12349), 0);
    expect(NetSalary.tariff(17799), greaterThan(1000));
    expect(NetSalary.tariff(100000), (0.42 * 100000 - 11135.63).floor());
  });

  test('3,000 € gross: 2,054.42 € net with the usual contributions', () {
    final r = NetSalary.compute(3000, age: 30);
    expect(r.pension, closeTo(279, 0.01));
    expect(r.unemployment, closeTo(39, 0.01));
    expect(r.health, closeTo(262.5, 0.01));
    expect(r.care, closeTo(72, 0.01));
    expect(r.soli, 0);
    expect(r.net, closeTo(2054.42, 0.01));
  });

  test('church tax, class III, and the solidarity surcharge at high pay', () {
    final church = NetSalary.compute(3000, age: 30, church: true, state: 'Hamburg');
    expect(church.churchTax, closeTo(293.08 * 0.09, 0.02));
    expect(NetSalary.compute(3000, age: 30, taxClass: 3).wageTax, lessThan(150));
    expect(NetSalary.compute(10000, age: 30).soli, greaterThan(0));
  });

  test('mini job, transition zone and working students are flagged', () {
    expect(NetSalary.compute(500).wageTax, 0);
    expect(NetSalary.compute(1800, age: 30).notes.join(), contains('Übergangsbereich'));
    final student = NetSalary.compute(1500, student: true);
    expect(student.health, 0);
    expect(student.pension, closeTo(139.5, 0.01));
  });

  test('care insurance: under 23 no surcharge, two children less', () {
    expect(NetSalary.careRate(children: 0, childlessSurcharge: false), 0.018);
    expect(NetSalary.careRate(children: 0, childlessSurcharge: true), closeTo(0.024, 1e-9));
    expect(NetSalary.careRate(children: 2, childlessSurcharge: true), closeTo(0.0155, 1e-9));
  });

  test('offline: a question with a gross amount gets the net right away', () {
    final a = LocalBuddy.netAnswer('was bleibt von 3.000 € brutto netto?')!;
    expect(a, contains('2.054,42'));
    expect(LocalBuddy.netAnswer('48000 brutto im jahr, steuerklasse 1, netto?'), contains('4.000,00'));
    expect(LocalBuddy.netAnswer('was ist brutto?'), isNull);
  });
}
