import 'package:test/test.dart';

import 'package:budget_buddy_backend/rate_limit.dart';

void main() {
  test('an address is blocked after its attempts and free again later', () {
    final limit = RateLimit(3, const Duration(minutes: 15));
    final t = DateTime(2026, 10, 27, 12);
    for (var i = 0; i < 3; i++) {
      expect(limit.blocked('1.2.3.4', now: t), isFalse);
      limit.hit('1.2.3.4', now: t);
    }
    expect(limit.blocked('1.2.3.4', now: t), isTrue);
    expect(limit.blocked('5.6.7.8', now: t), isFalse); // other addresses go on
    expect(limit.blocked('1.2.3.4', now: t.add(const Duration(minutes: 15))), isFalse);
  });
}
