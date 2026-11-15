import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/screens/transaction_screen.dart';
import 'package:budget_buddy/services/hints_service.dart';
import 'package:budget_buddy/services/oddities.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String id, int cents, String note, DateTime d, {String cat = 'Shopping', bool income = false}) =>
    Transaction(id: id, amountCents: cents, category: cat, date: d, isIncome: income, note: note);

void main() {
  final now = DateTime(2026, 11, 16); // a Monday

  test('the same merchant and amount within three days counts as charged twice', () {
    final tx = [
      _t('a', 4999, 'Zalando SE', DateTime(2026, 11, 10)),
      _t('b', 4999, 'ZALANDO', DateTime(2026, 11, 12)),
      _t('c', 4999, 'Zalando', DateTime(2026, 10, 1)), // too long ago
      _t('d', 320, 'Bäckerei', DateTime(2026, 11, 14)), // small things are often bought twice
      _t('e', 320, 'Bäckerei', DateTime(2026, 11, 15)),
      _t('f', 6000, 'Tankstelle', DateTime(2026, 11, 1)),
      _t('g', 6000, 'Tankstelle', DateTime(2026, 11, 8)), // a week apart: normal
    ];
    final d = Oddities.doubles(tx, now: now);
    expect(d.single.first.id, 'a');
    expect(d.single.second.id, 'b');
  });

  test('bank fees are summed by kind and projected to a year', () {
    final tx = [
      for (final m in [9, 10, 11]) _t('k$m', 495, 'Kontoführungsentgelt', DateTime(2026, m, 1), cat: 'Sonstiges'),
      _t('z', 1240, 'Sollzinsen Dispo', DateTime(2026, 10, 30), cat: 'Sonstiges'),
      _t('x', 175, 'Auslandseinsatzentgelt', DateTime(2026, 11, 3), cat: 'Sonstiges'),
    ];
    final fees = Oddities.fees(tx, now: now);
    expect({for (final f in fees) f.kind: f.cents}, {'konto': 1485, 'dispo': 1240, 'ausland': 175});
    expect(Oddities.yearly(fees), (2900 * 365 / 90).round());
  });

  test('hints: charged twice, fees, and the week on Monday', () {
    final tx = [
      _t('a', 4999, 'Zalando', DateTime(2026, 11, 12)),
      _t('b', 4999, 'Zalando', DateTime(2026, 11, 14)),
      for (final m in [9, 10, 11]) _t('k$m', 995, 'Kontoführung', DateTime(2026, m, 1), cat: 'Sonstiges'),
    ];
    final hints = HintsService.build(tx: tx, budgets: const [], goals: const [], freeCents: 30000, now: now);
    expect(hints.where((h) => h.kind == HintKind.doubleCharge).single.question, contains('zweimal'));
    expect(hints.where((h) => h.kind == HintKind.bankFees).single.title, contains('121,06'));
    // 300 € free for 15 days: 140 € this week
    expect(hints.where((h) => h.kind == HintKind.weekPlan).single.title, contains('140,00'));
    expect(
        HintsService.build(tx: tx, budgets: const [], goals: const [], freeCents: 30000, now: DateTime(2026, 11, 17))
            .where((h) => h.kind == HintKind.weekPlan),
        isEmpty);
  });

  test('the booking view asks Buddy about exactly this booking', () {
    expect(TransactionScreen.buddyQuestion(_t('a', 8999, 'Media Markt', DateTime(2026, 11, 14))),
        allOf(contains('89,99'), contains('Media Markt'), contains('leisten')));
    expect(TransactionScreen.buddyQuestion(_t('b', 50000, 'Oma', DateTime(2026, 11, 14), cat: 'Geschenk', income: true)),
        contains('Was mache ich am besten damit'));
  });
}
