import 'package:budget_buddy/services/payslip_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // a correct payslip for 3,000 € in class I, childless, 2.9 % additional contribution
  const fine = Payslip(
    brutto: 3000,
    netto: 2054.42,
    auszahlung: 2054.42,
    lohnsteuer: 293.08,
    rv: 279,
    av: 39,
    kv: 262.5,
    pv: 72,
    steuerklasse: 1,
    kirche: false,
  );

  test('a correct payslip: every line fits', () {
    final lines = PayslipCheck.lines(fine);
    expect(lines.every((l) => l.ok), isTrue, reason: lines.where((l) => !l.ok).map((l) => l.text).join());
    final a = PayslipCheck.answer(fine);
    expect(a, contains('stimmig'));
    expect(a, contains('Nächster Schritt:'));
  });

  test('too much wage tax and a pricey health insurer are pointed out', () {
    const p = Payslip(brutto: 3000, lohnsteuer: 450, kv: 271.5, rv: 279, av: 39, pv: 72, steuerklasse: 1);
    final lines = PayslipCheck.lines(p);
    final tax = lines.firstWhere((l) => l.label == 'Lohnsteuer');
    expect(tax.ok, isFalse);
    expect(tax.text, contains('290,66')); // with 3.5 % the insurance part of the tax-free allowance is higher
    // 271.50 € = 7.3 % + 1.75 %: 3.5 % additional, 0.6 points above average
    expect(lines.firstWhere((l) => l.label == 'Krankenversicherung').text, contains('Wechsel'));
    expect(PayslipCheck.answer(p), contains('Personalabteilung'));
  });

  test('class VI and a missing class are flagged, a company pension skips the recomputation', () {
    expect(PayslipCheck.lines(const Payslip(brutto: 2000, steuerklasse: 6)).first.ok, isFalse);
    expect(PayslipCheck.lines(const Payslip(brutto: 2000)).first.text, contains('Klasse I'));
    final bav = PayslipCheck.lines(const Payslip(brutto: 3000, bav: 100, lohnsteuer: 260, rv: 269.7, steuerklasse: 1));
    expect(bav.every((l) => l.ok), isTrue);
    expect(bav.last.label, 'Betriebsrente');
  });

  test('the photo comes with words about a payslip, or right after Buddy asked for one', () {
    expect(PayslipCheck.looksLike('Kannst du meine Abrechnung prüfen?'), isTrue);
    expect(PayslipCheck.looksLike('', lastAnswer: 'Schick mir ein Foto der Abrechnung'), isTrue);
    expect(PayslipCheck.looksLike('Kassenbon von Rewe'), isFalse);
  });
}
