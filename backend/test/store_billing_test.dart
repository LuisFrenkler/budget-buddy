import 'dart:convert';

import 'package:test/test.dart';

import 'package:budget_buddy_backend/billing.dart';
import 'package:budget_buddy_backend/store_billing.dart';

// a JWS as Apple sends it; only the payload matters here
String jws(Map payload) =>
    'eyJhbGciOiJFUzI1NiJ9.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.sig';

const products = PlusProducts();
final day = DateTime(2026, 10, 26);
int ms(DateTime d) => d.millisecondsSinceEpoch;

Map<String, dynamic> appleTx({
  String product = 'budgetbuddy_plus_yearly',
  String bundle = 'de.budgetbuddy.app',
  int? offerType,
  String? discount,
  Object? revoked,
}) =>
    {
      'originalTransactionId': '2000000111',
      'transactionId': '2000000222',
      'productId': product,
      'bundleId': bundle,
      'originalPurchaseDate': ms(day),
      'purchaseDate': ms(day),
      'expiresDate': ms(day.add(const Duration(days: 7))),
      if (offerType != null) 'offerType': offerType,
      if (discount != null) 'offerDiscountType': discount,
      if (revoked != null) 'revocationDate': revoked,
    };

Entitlement apple(Map tx, {int status = 1, Map? renewal, String env = 'Production'}) => appleEntitlement(
      transaction: tx,
      renewal: renewal,
      status: status,
      bundleId: 'de.budgetbuddy.app',
      products: products,
      environment: env,
    );

void main() {
  test('decodeJws reads the payload of an unpadded JWS', () {
    expect(decodeJws(jws({'productId': 'x', 'n': 1})), {'productId': 'x', 'n': 1});
    expect(() => decodeJws('nope'), throwsA(isA<BillingError>()));
  });

  group('App Store', () {
    test('free trial: trialing until it ends, renewing', () {
      final e = apple(appleTx(offerType: 1, discount: 'FREE_TRIAL'), renewal: {'autoRenewStatus': 1});
      expect(e.status, 'trialing');
      expect(e.active, isTrue);
      expect(e.plan, 'yearly');
      expect(e.trialEnds, day.add(const Duration(days: 7)));
      expect(e.cancelAtPeriodEnd, isFalse);
      expect(e.method, 'appStore');
      expect(e.subscription, '2000000111');
      expect(StoreBilling.owns(e), isTrue);
    });

    test('paid period without an offer is active, trial ends at the start', () {
      final e = apple(appleTx(product: 'budgetbuddy_plus_monthly'));
      expect(e.status, 'active');
      expect(e.plan, 'monthly');
      expect(e.trialEnds, day);
    });

    test('auto-renew switched off: runs until the end of the period', () {
      final e = apple(appleTx(), renewal: {'autoRenewStatus': 0});
      expect(e.active, isTrue);
      expect(e.cancelAtPeriodEnd, isTrue);
    });

    test('billing retry and grace period keep access, grace extends the period', () {
      expect(apple(appleTx(), status: 3).status, 'past_due');
      final grace = day.add(const Duration(days: 23));
      final e = apple(appleTx(), status: 4, renewal: {'gracePeriodExpiresDate': ms(grace)});
      expect(e.active, isTrue);
      expect(e.periodEnd, grace);
    });

    test('expired and revoked end access', () {
      expect(apple(appleTx(), status: 2).active, isFalse);
      expect(apple(appleTx(), status: 5).active, isFalse);
      // refunded by Apple while the status still says active
      expect(apple(appleTx(revoked: ms(day))).active, isFalse);
    });

    test('a purchase of another app or an unknown product is refused', () {
      expect(() => apple(appleTx(bundle: 'com.other.app')), throwsA(isA<BillingError>()));
      expect(() => apple(appleTx(product: 'coins_100')), throwsA(isA<BillingError>()));
    });

    test('sandbox purchases are remembered as such for later refreshes', () {
      expect(apple(appleTx(), env: 'Sandbox').customer, 'apple-sandbox');
      expect(apple(appleTx()).customer, 'apple');
    });
  });

  group('Google Play', () {
    Map<String, dynamic> purchase(String state,
            {String product = 'budgetbuddy_plus_monthly',
            bool renew = true,
            bool trial = false,
            DateTime? expires}) =>
        {
          'startTime': day.toUtc().toIso8601String(),
          'subscriptionState': state,
          'acknowledgementState': 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
          'lineItems': [
            {
              'productId': product,
              'expiryTime': (expires ?? day.add(const Duration(days: 7))).toUtc().toIso8601String(),
              'autoRenewingPlan': {'autoRenewEnabled': renew},
              'offerPhase': trial ? {'freeTrial': {}} : {'basePrice': {}},
            }
          ],
        };

    test('active free trial', () {
      final e = googleEntitlement(purchase('SUBSCRIPTION_STATE_ACTIVE', trial: true), 'tok', products, now: day);
      expect(e.status, 'trialing');
      expect(e.trialEnds.isAtSameMomentAs(day.add(const Duration(days: 7))), isTrue);
      expect(e.subscription, 'tok');
      expect(e.method, 'googlePlay');
    });

    test('active paid, yearly', () {
      final e = googleEntitlement(
          purchase('SUBSCRIPTION_STATE_ACTIVE', product: 'budgetbuddy_plus_yearly'), 'tok', products,
          now: day);
      expect(e.status, 'active');
      expect(e.plan, 'yearly');
      expect(e.cancelAtPeriodEnd, isFalse);
    });

    test('cancelled keeps access until expiry, then ends', () {
      final p = purchase('SUBSCRIPTION_STATE_CANCELED', renew: false);
      final running = googleEntitlement(p, 'tok', products, now: day);
      expect(running.active, isTrue);
      expect(running.cancelAtPeriodEnd, isTrue);
      final over = googleEntitlement(p, 'tok', products, now: day.add(const Duration(days: 8)));
      expect(over.active, isFalse);
    });

    test('grace period keeps access; on hold, paused, pending and expired do not', () {
      expect(googleEntitlement(purchase('SUBSCRIPTION_STATE_IN_GRACE_PERIOD'), 't', products, now: day).active,
          isTrue);
      for (final s in [
        'SUBSCRIPTION_STATE_ON_HOLD',
        'SUBSCRIPTION_STATE_PAUSED',
        'SUBSCRIPTION_STATE_PENDING',
        'SUBSCRIPTION_STATE_EXPIRED',
      ]) {
        expect(googleEntitlement(purchase(s), 't', products, now: day).active, isFalse, reason: s);
      }
    });

    test('an unknown product is refused', () {
      expect(() => googleEntitlement(purchase('SUBSCRIPTION_STATE_ACTIVE', product: 'coins'), 't', products),
          throwsA(isA<BillingError>()));
    });
  });

  group('StoreBilling', () {
    test('refuses stores without credentials', () {
      const none = StoreBilling();
      expect(none.mode, '');
      expect(() => none.verify('apple', '123'), throwsA(isA<BillingError>()));
      expect(() => none.verify('google', 'tok'), throwsA(isA<BillingError>()));
      expect(() => none.verify('apple', ' '), throwsA(isA<BillingError>()));
    });

    test('without credentials a known subscription runs out at its end', () async {
      const none = StoreBilling();
      final running = apple({...appleTx(), 'expiresDate': ms(DateTime.now().add(const Duration(days: 3)))});
      expect((await none.refresh(running)).active, isTrue);
      final over = apple({...appleTx(), 'expiresDate': ms(DateTime.now().subtract(const Duration(days: 1)))});
      expect((await none.refresh(over)).active, isFalse);
    });
  });
}
