import 'dart:convert';
import 'dart:io';

import 'package:budget_buddy_backend/product_counts.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bb_counts');
    file = File('${dir.path}/events.json');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('a kind belongs to a find and comes from the fixed list', () {
    expect(ProductCounts.allows('activated', null), isTrue);
    expect(ProductCounts.allows('find_shown', 'priceUp'), isTrue);
    expect(ProductCounts.allows('find_yes_tax', 'tax'), isTrue);
    expect(ProductCounts.allows('find_shown', 'Netflix 12,99'), isFalse);
    expect(ProductCounts.allows('find_shown', ''), isFalse);
    expect(ProductCounts.allows('activated', 'tax'), isFalse);
  });

  test('counts per UTC day, per name and per kind, and survives a restart', () async {
    final c = ProductCounts(file);
    // 00:30 in Berlin on the 2nd is still the 1st in UTC
    await c.add('find_shown', kind: 'tax', now: DateTime.parse('2026-11-02T00:30:00+01:00'));
    await c.add('find_shown', kind: 'priceUp', now: DateTime.utc(2026, 11, 2));
    await c.add('find_shown', kind: 'priceUp', now: DateTime.utc(2026, 11, 2));
    await c.add('activated', now: DateTime.utc(2026, 11, 2));

    final stored = jsonDecode(file.readAsStringSync()) as Map;
    expect(stored, {
      '2026-11-01': {'find_shown': 1, 'find_shown:tax': 1},
      '2026-11-02': {'find_shown': 2, 'find_shown:priceUp': 2, 'activated': 1},
    });
    expect(File('${file.path}.tmp').existsSync(), isFalse);

    final again = ProductCounts(file);
    await again.add('activated', now: DateTime.utc(2026, 11, 2));
    final s = again.summary(days: 30, now: DateTime.utc(2026, 11, 3));
    expect(s['byName'], {'find_shown': 3, 'activated': 2});
    expect(s['byKind'], {
      'find_shown': {'tax': 1, 'priceUp': 2}
    });
    expect((s['byDay'] as Map).keys, ['2026-11-01', '2026-11-02']);
  });

  test('the summary gives yes per shown for tax, money and each kind, and later per shown', () async {
    final c = ProductCounts(file);
    final t = DateTime.utc(2026, 11, 10);
    Future<void> many(int n, String name, String kind) async {
      for (var i = 0; i < n; i++) {
        await c.add(name, kind: kind, now: t);
      }
    }

    await many(4, 'find_shown', 'tax');
    await many(5, 'find_shown', 'priceUp');
    await many(5, 'find_shown', 'contracts');
    await many(1, 'find_yes_tax', 'tax');
    await many(2, 'find_yes_money', 'priceUp');
    await many(7, 'find_later', 'contracts');
    // older than the window: not counted
    await c.add('find_yes_tax', kind: 'tax', now: DateTime.utc(2026, 10, 1));

    final rates = c.summary(days: 7, now: DateTime.utc(2026, 11, 16))['rates'] as Map;
    expect(rates['yesTax'], {'yes': 1, 'shown': 4, 'rate': 0.25});
    expect(rates['yesMoney'], {'yes': 2, 'shown': 10, 'rate': 0.2});
    expect(rates['later'], {'yes': 7, 'shown': 14, 'rate': 0.5});
    expect(rates['yesByKind'], {
      'tax': {'yes': 1, 'shown': 4, 'rate': 0.25},
      'priceUp': {'yes': 2, 'shown': 5, 'rate': 0.4},
      'contracts': {'yes': 0, 'shown': 5, 'rate': 0.0},
    });
    expect(c.summary(days: 6, now: DateTime.utc(2026, 11, 16))['byName'], isEmpty);
  });

  test('finds without a kind give the rough rate, and nothing shown gives no rate', () async {
    final c = ProductCounts(file);
    expect((c.summary()['rates'] as Map)['yesTax'], {'yes': 0, 'shown': 0, 'rate': null});
    for (var i = 0; i < 4; i++) {
      await c.add('find_shown');
    }
    await c.add('find_yes_money');
    final rates = c.summary()['rates'] as Map;
    expect(rates['yesMoney'], {'yes': 1, 'shown': 4, 'rate': 0.25});
    expect(rates['yesByKind'], isEmpty);
  });
}
