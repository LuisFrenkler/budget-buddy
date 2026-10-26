import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/tx_search.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _t(String id, int cents, String cat, DateTime d, {String? note, bool income = false}) =>
    Transaction(id: id, amountCents: cents, category: cat, date: d, isIncome: income, note: note);

void main() {
  final tx = [
    _t('a', 2375, 'Essen & Trinken', DateTime(2026, 10, 25), note: 'Café'),
    _t('b', 8429, 'Lebensmittel', DateTime(2026, 10, 24), note: 'Aldi Süd'),
    _t('c', 12000, 'Kleidung', DateTime(2026, 9, 12), note: 'Zalando'),
    _t('d', 250000, 'Gehalt', DateTime(2026, 10, 1), note: 'Gehalt', income: true),
    _t('e', 2400, 'Unterhaltung', DateTime(2026, 9, 3), note: 'Kino'),
  ];
  List<String> ids(String q, {TxKind kind = TxKind.all}) => TxSearch.filter(tx, q, kind: kind).map((t) => t.id).toList();

  test('text, exact and rounded amounts', () {
    expect(ids('aldi'), ['b']);
    expect(ids('essen'), ['a']);
    expect(ids('23,75'), ['a']);
    expect(ids('24'), ['a', 'e']); // 23,75 rounds to 24
  });

  test('ranges, months, types', () {
    expect(ids('über 100'), ['c', 'd']);
    expect(ids('unter 25'), ['a', 'e']);
    expect(ids('september'), ['c', 'e']);
    expect(ids('einnahmen'), ['d']);
    expect(ids('ausgaben über 100'), ['c']);
    expect(ids('', kind: TxKind.income), ['d']);
    expect(TxSearch.total(TxSearch.filter(tx, 'oktober')), 250000 - 2375 - 8429);
  });
}
