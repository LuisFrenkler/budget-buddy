import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/category_coach.dart';
import 'package:budget_buddy/services/db.dart';
import 'dart:io';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bb_coach_');
    Hive.init(dir.path);
    await Hive.openBox('transactions');
    await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Transaction tx(String id, String note, String cat) => Transaction(
        id: id,
        amountCents: 1000,
        category: cat,
        date: DateTime(2026, 10, 1),
        isIncome: false,
        note: note,
      );

  test('apply only rewrites Sonstiges of that merchant', () async {
    await DB.addTx(tx('1', 'REWE Markt', 'Sonstiges'));
    await DB.addTx(tx('2', 'REWE Sagt Danke', 'Sonstiges'));
    await DB.addTx(tx('3', 'REWE Markt', 'Lebensmittel')); // already sorted
    await DB.addTx(tx('4', 'Lidl', 'Sonstiges'));

    final n = await CategoryCoach.apply('REWE Markt', 'Lebensmittel', isIncome: false);
    expect(n, 2);
    final all = DB.getTx();
    expect(all.firstWhere((t) => t.id == '1').category, 'Lebensmittel');
    expect(all.firstWhere((t) => t.id == '2').category, 'Lebensmittel');
    expect(all.firstWhere((t) => t.id == '3').category, 'Lebensmittel');
    expect(all.firstWhere((t) => t.id == '4').category, 'Sonstiges');
  });

  test('short noisy titles do not merge into one pile', () {
    // empty-ish keys must stay separate
    expect(
      CategoryCoach.groupKey('A', isIncome: false) !=
          CategoryCoach.groupKey('B', isIncome: false),
      isTrue,
    );
  });
}
