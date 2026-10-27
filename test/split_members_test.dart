import 'dart:io';
import 'package:budget_buddy/models/split.dart';
import 'package:budget_buddy/services/split_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('members').path);
    await Hive.openBox('splits');
    await Hive.openBox('settings');
  });

  test('a new person joins and a name changes; old balances stay with the right people', () async {
    final g = SplitGroup(id: 'wg', name: 'WG', emoji: '🏠', members: ['Ich', 'Lena'], expenses: [
      SplitExpense(
          id: 'e', title: 'Einkauf', cents: 3000, paidBy: 0, shares: SplitExpense.even(3000, [0, 1]),
          date: DateTime(2026, 10, 1)),
    ]);
    await SplitService.save(g);
    await SplitService.addMember(g, ' Tom ');
    await SplitService.renameMember(g, 1, 'Lena M.');
    final back = SplitService.byId('wg')!;
    expect(back.members, ['Ich', 'Lena M.', 'Tom']);
    expect(SplitMath.balances(back), [1500, -1500, 0]);
    expect(SplitService.normalizeCode(' ab12 cd\n'), 'AB12CD');
  });
}
