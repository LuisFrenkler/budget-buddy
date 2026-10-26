// BudgetBuddy Plus bought in the apps through the App Store or Google Play.
//
// The app never decides on its own that someone has Plus: after a purchase it
// sends the store's id for it (Apple: the transaction id, Google: the purchase
// token) and this server asks the store itself, with its own credentials,
// what was bought, until when, and whether it renews. The answer becomes the
// same Entitlement as a Stripe subscription (lib/billing.dart).
//
//   Apple   App Store Server API, authorised with a JWT (ES256) signed by an
//           In-App Purchase key from App Store Connect (.p8). Production is
//           asked first, then the sandbox (TestFlight and Xcode builds).
//   Google  Play Developer API (purchases.subscriptionsv2), authorised with a
//           service account that has access to the app in the Play Console.
//
// Without credentials for a store, purchases from it are refused: an
// unverified purchase never unlocks anything.
import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'billing.dart';

// the two products, with the same ids in App Store Connect and the Play Console
class PlusProducts {
  final String monthly;
  final String yearly;
  const PlusProducts({this.monthly = 'budgetbuddy_plus_monthly', this.yearly = 'budgetbuddy_plus_yearly'});

  bool known(String id) => id == monthly || id == yearly;
  String plan(String id) => id == yearly ? 'yearly' : 'monthly';
}

DateTime _ms(Object? v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : DateTime.fromMillisecondsSinceEpoch(0);

// the payload of a JWS from Apple (header.payload.signature, base64url)
Map<String, dynamic> decodeJws(String jws) {
  final parts = jws.split('.');
  if (parts.length != 3) throw const BillingError('Antwort des App Store nicht lesbar.');
  return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
}

// Apple's view of one subscription as an entitlement.
// [status]: 1 active, 2 expired, 3 billing retry, 4 grace period, 5 revoked.
Entitlement appleEntitlement({
  required Map transaction,
  Map? renewal,
  required int status,
  required String bundleId,
  required PlusProducts products,
  required String environment,
}) {
  if (transaction['bundleId'] != bundleId) throw const BillingError('Dieser Kauf gehört nicht zu BudgetBuddy.');
  final product = '${transaction['productId']}';
  if (!products.known(product)) throw const BillingError('Unbekanntes Produkt.');
  final started = _ms(transaction['originalPurchaseDate'] ?? transaction['purchaseDate']);
  final expires = _ms(transaction['expiresDate']);
  // an introductory offer without a discount type is a free trial on older iOS versions
  final trial = transaction['offerType'] == 1 &&
      (transaction['offerDiscountType'] == null || transaction['offerDiscountType'] == 'FREE_TRIAL');
  final revoked = transaction['revocationDate'] != null;
  final state = revoked
      ? 'canceled'
      : switch (status) {
          1 => trial ? 'trialing' : 'active',
          3 || 4 => 'past_due',
          _ => 'canceled',
        };
  final grace = renewal?['gracePeriodExpiresDate'];
  return Entitlement(
    plan: products.plan(product),
    status: state,
    started: started,
    trialEnds: trial ? expires : started,
    periodEnd: status == 4 && grace != null ? _ms(grace) : expires,
    cancelAtPeriodEnd: renewal != null && renewal['autoRenewStatus'] == 0,
    method: 'appStore',
    methodDetail: 'App Store',
    customer: environment == 'Sandbox' ? 'apple-sandbox' : 'apple',
    subscription: '${transaction['originalTransactionId']}',
    checked: DateTime.now(),
  );
}

// Google's view of one purchase token (SubscriptionPurchaseV2) as an entitlement
Entitlement googleEntitlement(Map purchase, String token, PlusProducts products, {DateTime? now}) {
  final items = (purchase['lineItems'] as List? ?? const []).cast<Map>();
  final item = items.where((i) => products.known('${i['productId']}')).firstOrNull;
  if (item == null) throw const BillingError('Unbekanntes Produkt.');
  final expires = DateTime.tryParse('${item['expiryTime']}') ?? DateTime.fromMillisecondsSinceEpoch(0);
  final started = DateTime.tryParse('${purchase['startTime']}') ?? DateTime.now();
  // the phase of the offer the current period belongs to
  final trial = (item['offerPhase'] as Map?)?.containsKey('freeTrial') == true;
  final running = (now ?? DateTime.now()).isBefore(expires);
  final state = switch ('${purchase['subscriptionState']}') {
    'SUBSCRIPTION_STATE_ACTIVE' => trial ? 'trialing' : 'active',
    'SUBSCRIPTION_STATE_IN_GRACE_PERIOD' => 'past_due',
    // cancelled but paid until the end of the period
    'SUBSCRIPTION_STATE_CANCELED' => running ? (trial ? 'trialing' : 'active') : 'canceled',
    'SUBSCRIPTION_STATE_PENDING' => 'incomplete',
    'SUBSCRIPTION_STATE_ON_HOLD' || 'SUBSCRIPTION_STATE_PAUSED' => 'paused',
    _ => 'canceled',
  };
  return Entitlement(
    plan: products.plan('${item['productId']}'),
    status: state,
    started: started,
    trialEnds: trial ? expires : started,
    periodEnd: expires,
    cancelAtPeriodEnd: (item['autoRenewingPlan'] as Map?)?['autoRenewEnabled'] != true,
    method: 'googlePlay',
    methodDetail: 'Google Play',
    customer: purchase['testPurchase'] != null ? 'google-test' : 'google',
    subscription: token,
    checked: DateTime.now(),
  );
}

class AppleStore {
  final String bundleId;
  final String issuerId;
  final String keyId;
  final String privateKeyPem; // the .p8 file
  final PlusProducts products;
  AppleStore({
    required this.bundleId,
    required this.issuerId,
    required this.keyId,
    required this.privateKeyPem,
    this.products = const PlusProducts(),
  });

  static const _production = 'https://api.storekit.itunes.apple.com';
  static const _sandbox = 'https://api.storekit-sandbox.itunes.apple.com';

  String? _jwt;
  DateTime _jwtExp = DateTime.fromMillisecondsSinceEpoch(0);

  // Apple accepts tokens for at most an hour
  String _token() {
    if (_jwt != null && DateTime.now().isBefore(_jwtExp)) return _jwt!;
    final jwt = JWT(
      {'bid': bundleId},
      issuer: issuerId,
      audience: Audience.one('appstoreconnect-v1'),
      header: {'kid': keyId, 'typ': 'JWT'},
    );
    _jwt = jwt.sign(ECPrivateKey(privateKeyPem), algorithm: JWTAlgorithm.ES256, expiresIn: const Duration(minutes: 30));
    _jwtExp = DateTime.now().add(const Duration(minutes: 25));
    return _jwt!;
  }

  // null when the id is unknown in this environment
  Future<Map<String, dynamic>?> _get(String base, String path) async {
    final res = await http.get(Uri.parse('$base$path'), headers: {'Authorization': 'Bearer ${_token()}'});
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 300) throw BillingError('App Store gerade nicht erreichbar (${res.statusCode}).');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // after a purchase or a restore: the transaction id from the device
  Future<Entitlement> verify(String transactionId) async {
    final id = Uri.encodeComponent(transactionId);
    for (final base in const [_production, _sandbox]) {
      final t = await _get(base, '/inApps/v1/transactions/$id');
      if (t == null) continue;
      final tx = decodeJws('${t['signedTransactionInfo']}');
      return _status(base, '${tx['originalTransactionId']}');
    }
    throw const BillingError('Diesen Kauf kennt der App Store nicht.');
  }

  Future<Entitlement> refresh(Entitlement e) =>
      _status(e.customer == 'apple-sandbox' ? _sandbox : _production, e.subscription);

  // the newest state of a subscription, with its renewal info
  Future<Entitlement> _status(String base, String originalTransactionId) async {
    final s = await _get(base, '/inApps/v1/subscriptions/${Uri.encodeComponent(originalTransactionId)}');
    final last = [
      for (final group in (s?['data'] as List? ?? const []).cast<Map>())
        ...(group['lastTransactions'] as List? ?? const []).cast<Map>(),
    ].where((t) => '${t['originalTransactionId']}' == originalTransactionId).firstOrNull;
    if (last == null) throw const BillingError('Dieses Abo kennt der App Store nicht.');
    return appleEntitlement(
      transaction: decodeJws('${last['signedTransactionInfo']}'),
      renewal: last['signedRenewalInfo'] == null ? null : decodeJws('${last['signedRenewalInfo']}'),
      status: (last['status'] as num?)?.toInt() ?? 2,
      bundleId: bundleId,
      products: products,
      environment: base == _sandbox ? 'Sandbox' : 'Production',
    );
  }
}

class GooglePlay {
  final String packageName;
  final Map<String, dynamic> serviceAccount; // the JSON key from Google Cloud
  final PlusProducts products;
  GooglePlay({required this.packageName, required this.serviceAccount, this.products = const PlusProducts()});

  static const _api = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';

  String? _access;
  DateTime _accessExp = DateTime.fromMillisecondsSinceEpoch(0);

  // OAuth for a service account: a signed JWT is exchanged for an access token
  Future<String> _token() async {
    if (_access != null && DateTime.now().isBefore(_accessExp)) return _access!;
    final tokenUri = '${serviceAccount['token_uri'] ?? 'https://oauth2.googleapis.com/token'}';
    final assertion = JWT(
      {'scope': 'https://www.googleapis.com/auth/androidpublisher'},
      issuer: '${serviceAccount['client_email']}',
      audience: Audience.one(tokenUri),
    ).sign(RSAPrivateKey('${serviceAccount['private_key']}'),
        algorithm: JWTAlgorithm.RS256, expiresIn: const Duration(hours: 1));
    final res = await http.post(Uri.parse(tokenUri), body: {
      'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      'assertion': assertion,
    });
    if (res.statusCode >= 300) throw BillingError('Google Play gerade nicht erreichbar (${res.statusCode}).');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    _access = '${body['access_token']}';
    _accessExp = DateTime.now().add(Duration(seconds: ((body['expires_in'] as num?) ?? 3600).toInt() - 120));
    return _access!;
  }

  String _base() => '$_api/${Uri.encodeComponent(packageName)}/purchases';

  // after a purchase or a restore: the purchase token from the device
  Future<Entitlement> verify(String token) async {
    final res = await http.get(
      Uri.parse('${_base()}/subscriptionsv2/tokens/${Uri.encodeComponent(token)}'),
      headers: {'Authorization': 'Bearer ${await _token()}'},
    );
    if (res.statusCode == 404 || res.statusCode == 400 || res.statusCode == 410) {
      throw const BillingError('Diesen Kauf kennt Google Play nicht.');
    }
    if (res.statusCode >= 300) throw BillingError('Google Play gerade nicht erreichbar (${res.statusCode}).');
    final purchase = jsonDecode(res.body) as Map<String, dynamic>;
    final e = googleEntitlement(purchase, token, products);
    // Google refunds purchases nobody acknowledged within three days; the app
    // does it too, this is the safety net
    if (purchase['acknowledgementState'] == 'ACKNOWLEDGEMENT_STATE_PENDING' && e.active) {
      final product = (purchase['lineItems'] as List).cast<Map>().first['productId'];
      await http.post(
        Uri.parse('${_base()}/subscriptions/${Uri.encodeComponent('$product')}'
            '/tokens/${Uri.encodeComponent(token)}:acknowledge'),
        headers: {'Authorization': 'Bearer ${await _token()}'},
      );
    }
    return e;
  }

  Future<Entitlement> refresh(Entitlement e) => verify(e.subscription);
}

// both stores behind one door; a store without credentials refuses
class StoreBilling {
  final AppleStore? apple;
  final GooglePlay? google;
  const StoreBilling({this.apple, this.google});

  static bool owns(Entitlement e) => e.method == 'appStore' || e.method == 'googlePlay';

  String get mode => [if (apple != null) 'apple', if (google != null) 'google'].join(',');

  Future<Entitlement> verify(String platform, String id) {
    if (id.trim().isEmpty) throw const BillingError('Kauf ohne Kennung.');
    return switch (platform) {
      'apple' when apple != null => apple!.verify(id),
      'google' when google != null => google!.verify(id),
      _ => throw const BillingError('Käufe aus diesem Store kann der Server noch nicht prüfen.'),
    };
  }

  Future<Entitlement> refresh(Entitlement e) => switch (e.method) {
        'appStore' when apple != null => apple!.refresh(e),
        'googlePlay' when google != null => google!.refresh(e),
        // no credentials any more: keep the last known state until it runs out
        _ => Future.value(DateTime.now().isAfter(e.periodEnd) ? e.copyWith(status: 'canceled') : e),
      };
}
