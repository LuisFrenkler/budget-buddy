import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:budget_buddy/services/backup_service.dart';
import 'package:budget_buddy/services/csv_importer.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/models/budget.dart';
import 'package:budget_buddy/models/holding.dart';

void main() {
  group('CSV export', () {
    test('round-trips through the importer without loss', () {
      final txs = [
        Transaction(
            id: '1', amountCents: 285000, category: 'Gehalt',
            date: DateTime(2025, 1, 5), isIncome: true, note: 'Lohn Januar'),
        Transaction(
            id: '2', amountCents: 6743, category: 'Lebensmittel',
            date: DateTime(2025, 1, 8), isIncome: false, note: 'REWE Einkauf'),
      ];

      final csv = BackupService.transactionsToCsv(txs);
      final reimported = CsvImporter.parse(csv).transactions;

      expect(reimported.length, 2);
      expect(reimported[0].amountCents, 285000);
      expect(reimported[0].isIncome, isTrue);
      expect(reimported[1].amountCents, 6743);
      expect(reimported[1].isIncome, isFalse);
      expect(reimported[1].note, 'REWE Einkauf');
    });
  });

  group('JSON backup / restore', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('bb_backup');
      Hive.init(tempDir.path);
      await Hive.openBox('transactions');
      await Hive.openBox('budgets');
      await Hive.openBox('badges');
      await Hive.openBox('holdings');
      await Hive.openBox('recurring');
    });

    tearDownAll(() async {
      await Hive.deleteFromDisk();
      tempDir.deleteSync(recursive: true);
    });

    test('restores transactions and budgets exactly', () async {
      await DB.addTx(Transaction(
          id: 'tx1', amountCents: 5000, category: 'Lebensmittel',
          date: DateTime(2025, 3, 5), isIncome: false));
      await DB.addBudget(Budget(
          category: 'Lebensmittel', limitCents: 25000,
          startDate: DateTime(2025, 3, 1), endDate: DateTime(2025, 3, 31)));
      await DB.addHolding(Holding(
          id: 'h1', name: 'Apple', symbol: 'AAPL', type: 'Aktie',
          shares: 10, buyPriceCents: 10000, currentPriceCents: 12000));

      final json = BackupService.toBackupJson();

      // wipe everything, then restore from the backup
      await Hive.box('transactions').clear();
      await Hive.box('budgets').clear();
      await Hive.box('holdings').clear();
      expect(DB.getTx(), isEmpty);

      await BackupService.restoreFromJson(json);

      expect(DB.getTx().length, 1);
      expect(DB.getTx().single.amountCents, 5000);
      final budget = DB.getBudgets().single;
      expect(budget.limitCents, 25000);
      expect(budget.spentCents, 5000); // recomputed from the restored transaction
      expect(DB.getHoldings().single.valueCents, 120000); // 10 * 120€
    });
  });
}
