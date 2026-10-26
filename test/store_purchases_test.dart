import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:budget_buddy/services/plus_service.dart';
import 'package:budget_buddy/services/store_purchases.dart';

PricingPhaseWrapper phase(String price, int micros) => PricingPhaseWrapper(
      billingCycleCount: micros == 0 ? 1 : 0,
      billingPeriod: micros == 0 ? 'P1W' : 'P1Y',
      formattedPrice: price,
      priceAmountMicros: micros,
      priceCurrencyCode: 'EUR',
      recurrenceMode: micros == 0 ? RecurrenceMode.finiteRecurring : RecurrenceMode.infiniteRecurring,
    );

// a yearly subscription with its base plan and a free-trial offer, as Google lists it
List<GooglePlayProductDetails> yearlyOffers() => GooglePlayProductDetails.fromProductDetails(ProductDetailsWrapper(
      description: 'Plus',
      name: 'Plus',
      productId: 'budgetbuddy_plus_yearly',
      productType: ProductType.subs,
      title: 'BudgetBuddy Plus',
      subscriptionOfferDetails: [
        SubscriptionOfferDetailsWrapper(
          basePlanId: 'yearly',
          offerTags: const [],
          offerIdToken: 'base-token',
          pricingPhases: [phase('39,99 €', 39990000)],
        ),
        SubscriptionOfferDetailsWrapper(
          basePlanId: 'yearly',
          offerId: 'free-trial',
          offerTags: const [],
          offerIdToken: 'trial-token',
          pricingPhases: [phase('Kostenlos', 0), phase('39,99 €', 39990000)],
        ),
      ],
    ));

Map<String, dynamic> entitlement({String method = 'appStore', bool cancel = false}) => {
      'plan': 'yearly',
      'status': 'trialing',
      'active': true,
      'started': '2026-10-26T10:00:00.000',
      'trialEnds': '2026-11-02T10:00:00.000',
      'periodEnd': '2026-11-02T10:00:00.000',
      'cancelAtPeriodEnd': cancel,
      'method': method,
      'methodDetail': method == 'appStore' ? 'App Store' : 'Google Play',
    };

void main() {
  group('Google Play offers', () {
    test('the free trial offer is bought when Google offers it', () {
      final offers = yearlyOffers();
      expect(offers, hasLength(2));
      final picked = StorePurchases.pickOffer(offers) as GooglePlayProductDetails;
      expect(picked.offerToken, 'trial-token');
    });

    test('without a trial offer the base plan is bought', () {
      final picked = StorePurchases.pickOffer([yearlyOffers().first]) as GooglePlayProductDetails;
      expect(picked.offerToken, 'base-token');
    });

    test('the price shown is the one after the trial, not "Kostenlos"', () {
      final trial = yearlyOffers().last;
      expect(trial.price, 'Kostenlos');
      expect(StorePurchases.regularPrice(trial), '39,99 €');
      expect(StorePurchases.regularPrice(yearlyOffers().first), '39,99 €');
    });
  });

  group('Plus from a store', () {
    late Box box;
    setUpAll(() async {
      Hive.init(Directory.systemTemp.createTempSync('store').path);
      box = await Hive.openBox('settings');
    });
    tearDown(PlusService.end);

    test('the server-checked purchase unlocks Plus and is remembered for later checks', () async {
      await PlusService.applyStore(entitlement(), platform: 'apple', id: '2000000222');
      final sub = PlusService.subscription.value!;
      expect(PlusService.active.value, isTrue);
      expect(sub.fromStore, isTrue);
      expect(sub.managed, isTrue);
      expect(sub.method, PayMethod.appStore);
      expect(sub.plan, PlusPlan.yearly);
      expect(sub.inTrial(DateTime(2026, 10, 30)), isTrue);
      expect(box.get('plusStore'), {'platform': 'apple', 'id': '2000000222'});
    });

    test('auto-renew off in the store shows as cancelled at the end of the period', () async {
      await PlusService.applyStore(entitlement(method: 'googlePlay', cancel: true), platform: 'google', id: 'tok');
      final sub = PlusService.subscription.value!;
      expect(sub.method, PayMethod.googlePlay);
      expect(sub.cancelled, isTrue);
      expect(sub.endsAt, DateTime(2026, 11, 2, 10));
    });

    test('the server saying "not active" ends it, but only for the same purchase', () async {
      await PlusService.applyStore(entitlement(), platform: 'apple', id: 'A');
      // an old, expired transaction of the same Apple ID changes nothing
      await PlusService.applyStore(null, platform: 'apple', id: 'B');
      expect(PlusService.active.value, isTrue);
      await PlusService.applyStore(null, platform: 'apple', id: 'A');
      expect(PlusService.active.value, isFalse);
      expect(box.get('plusStore'), isNull);
    });

    test('a test subscription is not a store one', () async {
      await PlusService.start(plan: PlusPlan.monthly, method: PayMethod.appStore);
      expect(PlusService.subscription.value!.fromStore, isFalse);
    });

    test('ending Plus also forgets the store purchase', () async {
      await PlusService.applyStore(entitlement(), platform: 'apple', id: 'A');
      await PlusService.end();
      expect(box.get('plusStore'), isNull);
      expect(PlusService.active.value, isFalse);
    });
  });

  test('until the store has answered, the paywall shows our own prices', () {
    expect(PlusService.price(PlusPlan.yearly), PlusService.yearlyPrice);
    expect(PlusService.price(PlusPlan.monthly), PlusService.monthlyPrice);
  });
}
