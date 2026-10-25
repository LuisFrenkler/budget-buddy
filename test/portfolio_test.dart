import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/models/holding.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('bb_portfolio');
    Hive.init(tempDir.path);
    await Hive.openBox('holdings');
  });

  tearDown(() async {
    await Hive.box('holdings').clear();
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    tempDir.deleteSync(recursive: true);
  });

  Holding h(String id, String name, double shares, int buy, int cur) =>
      Holding(id: id, name: name, symbol: '', type: 'Aktie',
          shares: shares, buyPriceCents: buy, currentPriceCents: cur);

  test('portfolio totals sum across holdings', () async {
    await DB.addHolding(h('1', 'Apple', 10, 10000, 12000)); // +200€
    await DB.addHolding(h('2', 'Tesla', 5, 20000, 18000));  // -100€

    expect(DB.portfolioInvested(), 200000);
    expect(DB.portfolioValue(), 210000);
    expect(DB.portfolioGain(), 10000);
  });

  test('holdings are sorted by value and allocation is per holding', () async {
    await DB.addHolding(h('1', 'Small', 1, 1000, 1000));
    await DB.addHolding(h('2', 'Big', 1, 5000, 9000));

    expect(DB.getHoldings().first.name, 'Big');
    final alloc = DB.holdingsAllocation();
    expect(alloc['Big'], 9000);
    expect(alloc['Small'], 1000);
  });
}
