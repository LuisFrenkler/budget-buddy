import 'package:budget_buddy/models/holding.dart';
import 'package:budget_buddy/services/backend_service.dart';
import 'package:budget_buddy/services/depot_sync.dart';
import 'package:budget_buddy/services/plus_service.dart';
import 'package:budget_buddy/services/price_service.dart';
import 'package:flutter_test/flutter_test.dart';

Holding _h(String id, {double shares = 1}) =>
    Holding(id: id, name: id, symbol: '', type: 'Aktie', shares: shares, buyPriceCents: 100, currentPriceCents: 100);

DepotPosition _p(String id, {double shares = 2, int price = 250}) =>
    DepotPosition(id, 'Name $id', '', 'ETF', shares, 200, price, 'Trade Republic');

void main() {
  group('DepotSync.merge', () {
    test('new positions get stable ids and the depot prices', () {
      final r = DepotSync.merge(existing: const [], incoming: [_p('IE00B4L5Y983')]);
      expect(r.keep.single.id, 'depot_IE00B4L5Y983');
      expect(r.keep.single.valueCents, 500);
      expect(r.keep.single.investedCents, 400);
      expect(r.added, 1);
      expect(r.remove, isEmpty);
    });

    test('syncing again updates instead of adding a copy', () {
      final r = DepotSync.merge(existing: [_h('depot_A')], incoming: [_p('A', shares: 5)]);
      expect(r.keep.single.id, 'depot_A');
      expect(r.keep.single.shares, 5);
      expect(r.added, 0);
    });

    test('a sold position is removed, hand-made ones are never touched', () {
      final r = DepotSync.merge(existing: [_h('depot_A'), _h('depot_B'), _h('manual_1')], incoming: [_p('A')]);
      expect(r.remove, ['depot_B']);
      expect(r.keep.map((h) => h.id), ['depot_A']);
    });

    test('positions without shares are skipped', () {
      final r = DepotSync.merge(existing: const [], incoming: [_p('A', shares: 0)]);
      expect(r.keep, isEmpty);
    });
  });

  group('Subscription.fromServer', () {
    final base = {
      'plan': 'yearly',
      'status': 'trialing',
      'started': '2026-10-01T10:00:00.000',
      'trialEnds': '2026-10-08T10:00:00.000',
      'periodEnd': '2026-10-08T10:00:00.000',
      'cancelAtPeriodEnd': false,
      'method': 'paypal',
      'methodDetail': 'me@example.com',
    };

    test('maps plan, method and trial and is marked as managed', () {
      final s = Subscription.fromServer(base);
      expect(s.plan, PlusPlan.yearly);
      expect(s.method, PayMethod.paypal);
      expect(s.methodText, 'me@example.com');
      expect(s.trialEnds, DateTime(2026, 10, 8, 10));
      expect(s.managed, isTrue);
      expect(s.cancelled, isFalse);
    });

    test('a cancellation runs until the end of the period', () {
      final s = Subscription.fromServer({...base, 'cancelAtPeriodEnd': true});
      expect(s.endsAt, DateTime(2026, 10, 8, 10));
    });

    test('an unknown method falls back to card', () {
      expect(Subscription.fromServer({...base, 'method': 'bancontact'}).method, PayMethod.card);
    });

    test('managed survives storing', () {
      final s = Subscription.fromServer(base);
      expect(Subscription.fromMap(s.toMap()).managed, isTrue);
      expect(Subscription.fromMap(s.copyWith(plan: PlusPlan.monthly).toMap()).managed, isTrue);
    });
  });

  group('PriceService.linkedHistory', () {
    final axis = [for (var d = 1; d <= 5; d++) DateTime(2026, 10, d)];

    test('takes the last value on or before each day and ends at the current value', () {
      final h = PriceService.linkedHistory([
        (DateTime(2026, 10, 1), 1000),
        (DateTime(2026, 10, 3), 1200),
        (DateTime(2026, 10, 5), 1500),
      ], axis, 1500);
      expect(h, [1000, 1000, 1200, 1200, 1500]);
    });

    test('is scaled so chart and headline agree', () {
      final h = PriceService.linkedHistory([(DateTime(2026, 10, 1), 1000), (DateTime(2026, 10, 5), 2000)], axis, 1000);
      expect(h.first, 500);
      expect(h.last, 1000);
    });

    test('zero before the depot existed', () {
      final h = PriceService.linkedHistory([(DateTime(2026, 10, 3), 800)], axis, 800);
      expect(h, [0, 0, 800, 800, 800]);
    });

    test('today is the current value even without a point for today', () {
      final h = PriceService.linkedHistory([(DateTime(2026, 10, 1), 1000), (DateTime(2026, 10, 4), 1100)], axis, 1234);
      expect(h.last, 1234);
    });
  });
}
