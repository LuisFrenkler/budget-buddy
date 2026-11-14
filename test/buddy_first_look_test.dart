import 'package:budget_buddy/services/buddy_first_look.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/buddy_eval/dataset.dart';

void main() {
  final now = DateTime(2026, 11, 14);

  test('three exact findings and a next step for the test person', () {
    final look = BuddyFirstLook.build(EvalData.tools(now))!;
    expect(look.points.length, 3);
    // the price rise of a subscription comes first
    expect(look.points.first, contains('teurer geworden'));
    // last month's shopping was far above the usual
    expect(look.points[1], contains('Shopping'));
    expect(look.text, contains('Nächster Schritt: '));
    expect(look.followUps.length, 2);
  });

  test('not before there is enough to say something real', () {
    final few = EvalData.tools(now);
    final t = BuddyTools(tx: few.tx.where((x) => now.difference(x.date).inDays < 10).toList(), snapshot: few.snapshot, now: now);
    expect(BuddyFirstLook.build(t), isNull);
  });
}
