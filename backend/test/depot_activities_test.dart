import 'package:test/test.dart';

import 'package:budget_buddy_backend/depot.dart';

void main() {
  test('a position Parqet sends as placeholder is counted from its bookings', () {
    // Solana as it came from Parqet: buys, a sell, then weekly staking rewards
    final r = ParqetConnect.fromActivities([
      {'type': 'transfer_in', 'datetime': '2026-10-19T07:39:45Z', 'shares': 0.5, 'price': 90.0},
      {'type': 'buy', 'datetime': '2024-12-05T09:28:48Z', 'shares': 5, 'price': 200.0},
      {'type': 'sell', 'datetime': '2025-09-14T12:16:33Z', 'shares': 4, 'price': 210.0},
      {'type': 'buy', 'datetime': '2025-10-10T22:29:21Z', 'shares': 3, 'price': 100.0},
      {'type': 'dividend', 'datetime': '2025-11-01T00:00:00Z', 'shares': 0, 'price': 0},
    ]);
    expect(r.shares, closeTo(4.5, 1e-9));
    // 1 left at 200 + 3 at 100 + 0.5 at 90 = 545 for 4.5
    expect(r.buyPrice, closeTo(545 / 4.5, 1e-9));
  });

  test('a fully sold coin is no position', () {
    final r = ParqetConnect.fromActivities([
      {'type': 'buy', 'datetime': '2024-01-01', 'shares': 5796.747852 + 5796.747851, 'price': 0.1},
      {'type': 'sell', 'datetime': '2024-02-01', 'shares': 5796.747852, 'price': 0.2},
      {'type': 'sell', 'datetime': '2024-02-02', 'shares': 5796.747851, 'price': 0.2},
    ]);
    expect(r.shares, 0);
  });
}
