// BudgetBuddy Plus in the iPhone and Android app: bought through the App
// Store or Google Play (in_app_purchase), as both stores require for digital
// subscriptions.
//
// The store takes the payment, the server decides: every purchase the store
// reports (new, restored, renewed) goes to the backend, which asks Apple or
// Google itself (backend/lib/store_billing.dart). Only that answer unlocks
// Plus. A purchase is finished with the store (completePurchase) after the
// server has seen it, so one that could not be checked is delivered again.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:url_launcher/url_launcher.dart';

import 'backend_service.dart';
import 'plus_service.dart';

enum StoreResult { done, cancelled, pending }

class StoreError implements Exception {
  final String message;
  const StoreError(this.message);
  @override
  String toString() => message;
}

class StorePurchases {
  // the same ids in App Store Connect and the Play Console
  static const ids = {
    PlusPlan.monthly: 'budgetbuddy_plus_monthly',
    PlusPlan.yearly: 'budgetbuddy_plus_yearly',
  };

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  static String get platform => defaultTargetPlatform == TargetPlatform.iOS ? 'apple' : 'google';

  static String get storeName => platform == 'apple' ? 'App Store' : 'Google Play';

  // the store's own, localized price per plan, once loaded
  static final prices = ValueNotifier<Map<PlusPlan, String>>({});

  static InAppPurchase get _iap => InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _sub;
  static final _products = <PlusPlan, ProductDetails>{};
  static Completer<StoreResult>? _buying;
  static Completer<void>? _restoring;

  // listens for purchases; called once at start, so renewals and purchases
  // left over from a crash are picked up too
  static void init() {
    if (!supported || _sub != null) return;
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) => _fail('$e'));
    loadProducts();
    // Android delivers unfinished purchases only when asked; it shows no dialog
    if (platform == 'google') _iap.restorePurchases();
  }

  static Future<bool> loadProducts() async {
    if (!supported || !await _iap.isAvailable()) return false;
    final res = await _iap.queryProductDetails(ids.values.toSet());
    for (final plan in PlusPlan.values) {
      final offers = res.productDetails.where((p) => p.id == ids[plan]).toList();
      if (offers.isNotEmpty) _products[plan] = pickOffer(offers);
    }
    prices.value = {for (final e in _products.entries) e.key: regularPrice(e.value)};
    return _products.length == PlusPlan.values.length;
  }

  // Google lists the base plan and every offer the user may take; the free
  // trial wins when there is one
  static ProductDetails pickOffer(List<ProductDetails> offers) {
    for (final o in offers) {
      if (o is GooglePlayProductDetails && _phases(o).any((p) => p.priceAmountMicros == 0)) return o;
    }
    return offers.first;
  }

  // the price after any trial: Google's first phase of a trial offer is "free"
  static String regularPrice(ProductDetails p) {
    if (p is GooglePlayProductDetails) {
      final phases = _phases(p);
      if (phases.isNotEmpty) return phases.last.formattedPrice;
    }
    return p.price;
  }

  static List<PricingPhaseWrapper> _phases(GooglePlayProductDetails p) {
    final i = p.subscriptionIndex;
    final offers = p.productDetails.subscriptionOfferDetails;
    return i == null || offers == null ? const [] : offers[i].pricingPhases;
  }

  // opens the store's purchase sheet; done once the server has confirmed it
  static Future<StoreResult> buy(PlusPlan plan) async {
    if (_products[plan] == null && !await loadProducts()) {
      throw StoreError('Der $storeName ist gerade nicht erreichbar. Bitte versuch es gleich noch einmal.');
    }
    final product = _products[plan];
    if (product == null) throw StoreError('Plus ist im $storeName gerade nicht verfügbar.');
    _buying = Completer<StoreResult>();
    // subscriptions are bought like non-consumables
    final started = await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
    if (!started) _finish(StoreResult.cancelled);
    return _buying!.future;
  }

  // "Käufe wiederherstellen": the store reports what this Apple ID or Google
  // account owns, each is checked by the server
  static Future<void> restore() async {
    if (!supported || !await _iap.isAvailable()) return;
    _restoring = Completer<void>();
    await _iap.restorePurchases();
    // a store with nothing to restore reports nothing at all
    await _restoring!.future.timeout(const Duration(seconds: 12), onTimeout: () {});
    _restoring = null;
  }

  static Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.pending:
          // e.g. "Ask to Buy" or a slow payment method: Plus comes once it is paid
          _finish(StoreResult.pending);
        case PurchaseStatus.canceled:
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          _finish(StoreResult.cancelled);
        case PurchaseStatus.error:
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          _fail(p.error?.message ?? 'Der Kauf hat nicht geklappt.');
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          await _verify(p);
      }
    }
    if (_restoring?.isCompleted == false) _restoring!.complete();
  }

  static Future<void> _verify(PurchaseDetails p) async {
    if (!ids.containsValue(p.productID)) {
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
      return;
    }
    // Apple: the transaction id, Google: the purchase token
    final id = platform == 'apple' ? p.purchaseID : p.verificationData.serverVerificationData;
    if (id == null || id.isEmpty) return _fail('Der Kauf kam ohne Kennung zurück.');
    try {
      await PlusService.applyStore(await BackendService.plusStore(platform, id), platform: platform, id: id);
    } catch (e) {
      // not finished with the store: it comes back and is checked again
      return _fail('Dein Kauf ist angekommen, konnte aber noch nicht bestätigt werden ($e). '
          'Er wird automatisch nachgeholt.');
    }
    if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    _finish(StoreResult.done);
  }

  static void _finish(StoreResult r) {
    if (_buying?.isCompleted == false) _buying!.complete(r);
  }

  static void _fail(String message) {
    if (_buying?.isCompleted == false) _buying!.completeError(StoreError(message));
  }

  // cancelling, the plan and receipts of a store subscription live in the store
  static Future<void> manage() => launchUrl(
        Uri.parse(platform == 'apple'
            ? 'https://apps.apple.com/account/subscriptions'
            : 'https://play.google.com/store/account/subscriptions'),
        mode: LaunchMode.externalApplication,
      );

  // refunds of store purchases are granted by Apple or Google, not by us
  static Future<void> requestRefund() => launchUrl(
        Uri.parse(platform == 'apple'
            ? 'https://reportaproblem.apple.com'
            : 'https://play.google.com/store/account/orderhistory'),
        mode: LaunchMode.externalApplication,
      );
}
