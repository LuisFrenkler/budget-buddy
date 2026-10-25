import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/demo_data.dart';

void main() {
  late Directory tempDir;
  final now = DateTime(2026, 3, 15, 18);

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('bb_demo_test');
    Hive.init(tempDir.path);
    for (final name in ['transactions', 'budgets', 'badges', 'holdings']) {
      await Hive.openBox(name);
    }
    // no DB.initBadges() here on purpose: loading demo data from the
    // onboarding happens before the home screen ever created the badges
    await DemoData.load(now: now);
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    tempDir.deleteSync(recursive: true);
  });

  group('DemoData', () {
    test('never creates transactions in the future', () {
      expect(DB.getTx().where((t) => t.date.isAfter(now)), isEmpty);
    });

    test('fills each of the last six months', () {
      final tx = DB.getTx();
      for (int i = 0; i < 6; i++) {
        expect(DB.inMonth(tx, DateTime(now.year, now.month - i)), isNotEmpty);
      }
      expect(DB.inMonth(tx, DateTime(now.year, now.month - 6)), isEmpty);
    });

    test('ends up with a positive balance and unlocked badges', () {
      expect(DB.balance(), greaterThan(0));
      expect(DB.getBadges().where((b) => b.isUnlocked).length, 4);
    });

    test('creates a portfolio and budgets for the current month', () {
      expect(DB.getHoldings().length, 5);
      final budgets = DB.getBudgets();
      expect(budgets.length, 3);
      expect(budgets.every((b) => b.startDate == DateTime(2026, 3, 1)), isTrue);
    });
  });
}
