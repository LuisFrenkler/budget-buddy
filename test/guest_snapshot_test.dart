import 'dart:io';

import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_service.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/demo_data.dart';
import 'package:budget_buddy/services/local_buddy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('bb_guest_snap');
    Hive.init(dir.path);
    await Hive.openBox('transactions');
    await Hive.openBox('budgets');
    await Hive.openBox('badges');
    await Hive.openBox('holdings');
    await Hive.openBox('recurring');
    await Hive.openBox('goals');
    await Hive.openBox('splits');
    await Hive.openBox('settings');
    DemoData.guestSessionActive = false;
  });

  tearDown(() async {
    DemoData.guestSessionActive = false;
    await Hive.deleteFromDisk();
    dir.deleteSync(recursive: true);
  });

  test('unsigned Buddy ignores leftover Hive Netflix/Spotify bookings', () async {
    final now = DateTime.now();
    for (var i = 0; i < 4; i++) {
      final d = DateTime(now.year, now.month - i, 5);
      await DB.addTx(Transaction(
        id: 'netflix_$i',
        amountCents: 1299,
        category: 'Unterhaltung',
        note: 'Netflix',
        date: d,
        isIncome: false,
      ));
      await DB.addTx(Transaction(
        id: 'spotify_$i',
        amountCents: 1199,
        category: 'Unterhaltung',
        note: 'Spotify',
        date: d,
        isIncome: false,
      ));
      await DB.addTx(Transaction(
        id: 'transport_$i',
        amountCents: 8900,
        category: 'Transport',
        note: 'Tankstelle',
        date: d,
        isIncome: false,
      ));
    }

    expect(DB.getTx(), isNotEmpty);
    expect(DemoData.guestSessionActive, isFalse);

    final snap = BuddyService.snapshot();
    expect(snap.current.expenses, 0);
    expect(snap.contracts, isEmpty);

    final answer = LocalBuddy.answer('Wo kann ich sparen?', snap);
    expect(answer.toLowerCase(), isNot(contains('netflix')));
    expect(answer.toLowerCase(), isNot(contains('spotify')));
    expect(answer.toLowerCase(), isNot(contains('24,98')));
  });

  test('guest Beispieldaten session may use loaded ledger', () async {
    DemoData.guestSessionActive = true;
    await DB.addTx(Transaction(
      id: 'demo_1',
      amountCents: 500,
      category: 'Essen',
      date: DateTime.now(),
      isIncome: false,
    ));
    final snap = BuddyService.snapshot();
    expect(snap.current.expenses, 500);
  });
}
