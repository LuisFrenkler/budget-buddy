import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:budget_buddy/models/recurring.dart';
import 'package:budget_buddy/services/recurring_service.dart';
import 'package:budget_buddy/services/db.dart';

void main() {
  group('RecurringService.advance', () {
    test('monthly clamps to the last day of short months', () {
      // Jan 31 + 1 month -> Feb 28 (2025 is not a leap year)
      expect(RecurringService.advance(DateTime(2025, 1, 31), 'monatlich'),
          DateTime(2025, 2, 28));
    });

    test('monthly rolls over the year', () {
      expect(RecurringService.advance(DateTime(2025, 12, 15), 'monatlich'),
          DateTime(2026, 1, 15));
    });

    test('yearly clamps Feb 29 to Feb 28', () {
      expect(RecurringService.advance(DateTime(2024, 2, 29), 'jährlich'),
          DateTime(2025, 2, 28));
    });

    test('weekly and daily', () {
      expect(RecurringService.advance(DateTime(2025, 3, 1), 'wöchentlich'),
          DateTime(2025, 3, 8));
      expect(RecurringService.advance(DateTime(2025, 3, 1), 'täglich'),
          DateTime(2025, 3, 2));
    });
  });

  group('RecurringService.dueOccurrences', () {
    RecurringRule rule({DateTime? start, DateTime? lastRun, bool active = true}) =>
        RecurringRule(
          id: 'r', amountCents: 1000, category: 'Gehalt', isIncome: true,
          interval: 'monatlich',
          startDate: start ?? DateTime(2025, 1, 15),
          lastRun: lastRun, active: active);

    test('backfills every occurrence up to today', () {
      final due = RecurringService.dueOccurrences(rule(), DateTime(2025, 3, 20));
      expect(due, [DateTime(2025, 1, 15), DateTime(2025, 2, 15), DateTime(2025, 3, 15)]);
    });

    test('nothing due before the next occurrence', () {
      final due = RecurringService.dueOccurrences(
          rule(lastRun: DateTime(2025, 3, 15)), DateTime(2025, 3, 20));
      expect(due, isEmpty);
    });

    test('inactive and future-dated rules produce nothing', () {
      expect(RecurringService.dueOccurrences(rule(active: false), DateTime(2025, 3, 20)), isEmpty);
      expect(RecurringService.dueOccurrences(
          rule(start: DateTime(2030, 1, 1)), DateTime(2025, 3, 20)), isEmpty);
    });

    test('resuming a paused rule skips the dates missed while paused', () {
      // paused after January, switched back on in April
      final r = rule(lastRun: DateTime(2025, 1, 15));
      RecurringService.skipPaused(r, DateTime(2025, 4, 10));
      expect(r.lastRun, DateTime(2025, 3, 15));
      expect(RecurringService.dueOccurrences(r, DateTime(2025, 4, 10)), isEmpty);
      expect(RecurringService.dueOccurrences(r, DateTime(2025, 4, 15)), [DateTime(2025, 4, 15)]);
    });

    test('resuming on a due day still books that day', () {
      final r = rule(lastRun: DateTime(2025, 1, 15));
      RecurringService.skipPaused(r, DateTime(2025, 4, 15));
      expect(RecurringService.dueOccurrences(r, DateTime(2025, 4, 15)), [DateTime(2025, 4, 15)]);
    });
  });

  group('RecurringService.process', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('bb_recurring');
      Hive.init(tempDir.path);
      await Hive.openBox('transactions');
      await Hive.openBox('badges');
      await Hive.openBox('recurring');
    });

    tearDown(() async {
      await Hive.box('transactions').clear();
      await Hive.box('recurring').clear();
      await Hive.box('badges').clear();
    });

    tearDownAll(() async {
      await Hive.deleteFromDisk();
      tempDir.deleteSync(recursive: true);
    });

    test('generates transactions once and is idempotent', () async {
      await DB.addRule(RecurringRule(
        id: 'salary', amountCents: 285000, category: 'Gehalt', isIncome: true,
        interval: 'monatlich', startDate: DateTime(2025, 1, 15)));

      final created = await RecurringService.process();
      expect(created, greaterThan(0));
      expect(DB.getTx().length, created);
      expect(DB.getTx().every((t) => t.category == 'Gehalt'), isTrue);

      // running again must not duplicate anything
      final again = await RecurringService.process();
      expect(again, 0);
      expect(DB.getTx().length, created);
    });
  });
}
