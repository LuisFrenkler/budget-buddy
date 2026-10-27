// BudgetBuddy Plus payments on the web through Stripe (https://stripe.com).
//
// The app never sees card or bank details: it asks this server for a Stripe
// Checkout page, the user pays there (card, PayPal, SEPA, Apple Pay, Google
// Pay, Klarna, whatever is switched on in the Stripe dashboard), and the
// server records who has Plus. Changing the payment method, the plan and
// downloading invoices happen in Stripe's customer portal.
//
// The entitlement is updated three ways, so it works with and without a
// public webhook URL: on the return from checkout, from Stripe webhooks, and
// by re-reading the subscription when the app asks and the copy is old.
//
// Without STRIPE_SECRET_KEY the server runs a demo checkout with the same
// steps that never charges anything.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'net.dart';

// what the app needs to know about one user's Plus
class Entitlement {
  final String plan; // 'monthly' | 'yearly'
  final String status; // trialing, active, past_due, canceled, ...
  final DateTime started;
  final DateTime trialEnds;
  final DateTime periodEnd;
  final bool cancelAtPeriodEnd;
  final String method; // card, paypal, sepa, ... (PayMethod names in the app)
  final String methodDetail; // e.g. "Visa •••• 4242"
  final String customer;
  final String subscription;
  final DateTime checked;

  const Entitlement({
    required this.plan,
    required this.status,
    required this.started,
    required this.trialEnds,
    required this.periodEnd,
    required this.cancelAtPeriodEnd,
    required this.method,
    required this.methodDetail,
    required this.customer,
    required this.subscription,
    required this.checked,
  });

  bool get active => const {'trialing', 'active', 'past_due'}.contains(status);

  Map<String, dynamic> toJson() => {
        'plan': plan,
        'status': status,
        'active': active,
        'started': started.toIso8601String(),
        'trialEnds': trialEnds.toIso8601String(),
        'periodEnd': periodEnd.toIso8601String(),
        'cancelAtPeriodEnd': cancelAtPeriodEnd,
        'method': method,
        'methodDetail': methodDetail,
        'customer': customer,
        'subscription': subscription,
        'checked': checked.toIso8601String(),
      };

  static Entitlement fromJson(Map m) => Entitlement(
        plan: '${m['plan']}',
        status: '${m['status']}',
        started: DateTime.parse('${m['started']}'),
        trialEnds: DateTime.parse('${m['trialEnds']}'),
        periodEnd: DateTime.parse('${m['periodEnd']}'),
        cancelAtPeriodEnd: m['cancelAtPeriodEnd'] == true,
        method: '${m['method'] ?? 'card'}',
        methodDetail: '${m['methodDetail'] ?? ''}',
        customer: '${m['customer'] ?? ''}',
        subscription: '${m['subscription'] ?? ''}',
        checked: DateTime.tryParse('${m['checked']}') ?? DateTime(2000),
      );

  Entitlement copyWith({String? status, bool? cancelAtPeriodEnd}) => Entitlement(
        plan: plan,
        status: status ?? this.status,
        started: started,
        trialEnds: trialEnds,
        periodEnd: periodEnd,
        cancelAtPeriodEnd: cancelAtPeriodEnd ?? this.cancelAtPeriodEnd,
        method: method,
        methodDetail: methodDetail,
        customer: customer,
        subscription: subscription,
        checked: DateTime.now(),
      );
}

class BillingError implements Exception {
  final String message;
  const BillingError(this.message);
  @override
  String toString() => message;
}

abstract class Billing {
  String get mode; // 'live' or 'demo'
  // a checkout page for [plan]; [returnUrl] gets ?session_id= appended by the provider
  Future<String> checkout({
    required String user,
    required String email,
    required String plan,
    required int trialDays,
    required String returnUrl,
    required String cancelUrl,
    String? customer,
  });
  // after the checkout: the session's subscription, or null when not paid
  Future<Entitlement?> fromSession(String sessionId);
  Future<Entitlement> refresh(Entitlement e);
  Future<String> portal(Entitlement e, String returnUrl);
  Future<Entitlement> setCancel(Entitlement e, bool cancel);
  // the 14-day withdrawal: ends right away and refunds what was paid
  Future<Entitlement> withdraw(Entitlement e);
}

DateTime _ts(Object? seconds) =>
    seconds is num ? DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000) : DateTime.now();

class StripeBilling implements Billing {
  static const _base = 'https://api.stripe.com/v1';
  final String secretKey;
  final String priceMonthly;
  final String priceYearly;
  StripeBilling({required this.secretKey, required this.priceMonthly, required this.priceYearly});

  @override
  String get mode => 'live';

  Future<Map<String, dynamic>> _req(String method, String path, [Map<String, String>? form]) async {
    final headers = {'Authorization': 'Bearer $secretKey'};
    final uri = Uri.parse('$_base$path');
    final res = switch (method) {
      'GET' => await net.get(uri, headers: headers),
      'DELETE' => await net.delete(uri, headers: headers),
      _ => await net.post(uri, headers: headers, body: form),
    };
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 300) {
      throw BillingError('Zahlung gerade nicht möglich: ${(body['error'] as Map?)?['message'] ?? res.statusCode}');
    }
    return body;
  }

  @override
  Future<String> checkout({
    required String user,
    required String email,
    required String plan,
    required int trialDays,
    required String returnUrl,
    required String cancelUrl,
    String? customer,
  }) async {
    final s = await _req('POST', '/checkout/sessions', {
      'mode': 'subscription',
      'line_items[0][price]': plan == 'yearly' ? priceYearly : priceMonthly,
      'line_items[0][quantity]': '1',
      'subscription_data[trial_period_days]': '$trialDays',
      'subscription_data[metadata][user]': user,
      'client_reference_id': user,
      if (customer != null && customer.isNotEmpty) 'customer': customer else 'customer_email': email,
      'locale': 'de',
      'success_url': '$returnUrl${returnUrl.contains('?') ? '&' : '?'}session_id={CHECKOUT_SESSION_ID}',
      'cancel_url': cancelUrl,
    });
    return '${s['url']}';
  }

  @override
  Future<Entitlement?> fromSession(String sessionId) async {
    final s = await _req('GET', '/checkout/sessions/${Uri.encodeComponent(sessionId)}');
    final sub = s['subscription'];
    if (sub == null) return null;
    return _read('$sub', '${s['customer'] ?? ''}');
  }

  Future<Entitlement> _read(String subscriptionId, [String customer = '']) async {
    final s = await _req('GET', '/subscriptions/$subscriptionId?expand[]=default_payment_method');
    final item = ((s['items'] as Map?)?['data'] as List?)?.cast<Map>().firstOrNull;
    final price = '${(item?['price'] as Map?)?['id'] ?? ''}';
    // newer API versions keep the period on the item, older ones on the subscription
    final periodEnd = item?['current_period_end'] ?? s['current_period_end'];
    final (method, detail) = _method(s['default_payment_method'] as Map?);
    return Entitlement(
      plan: price == priceYearly ? 'yearly' : 'monthly',
      status: '${s['status']}',
      started: _ts(s['start_date']),
      trialEnds: s['trial_end'] == null ? _ts(s['start_date']) : _ts(s['trial_end']),
      periodEnd: _ts(periodEnd),
      cancelAtPeriodEnd: s['cancel_at_period_end'] == true || s['cancel_at'] != null,
      method: method,
      methodDetail: detail,
      customer: customer.isNotEmpty ? customer : '${s['customer']}',
      subscription: subscriptionId,
      checked: DateTime.now(),
    );
  }

  static (String, String) _method(Map? pm) {
    if (pm == null) return ('card', '');
    switch (pm['type']) {
      case 'card':
        final c = pm['card'] as Map;
        final wallet = (c['wallet'] as Map?)?['type'];
        final brand = '${c['brand']}';
        final name = brand.isEmpty ? 'Karte' : brand[0].toUpperCase() + brand.substring(1);
        if (wallet == 'apple_pay') return ('applePay', 'Apple Pay · $name •••• ${c['last4']}');
        if (wallet == 'google_pay') return ('googlePay', 'Google Pay · $name •••• ${c['last4']}');
        return ('card', '$name •••• ${c['last4']}');
      case 'sepa_debit':
        return ('sepa', 'IBAN •••• ${(pm['sepa_debit'] as Map)['last4']}');
      case 'paypal':
        return ('paypal', '${(pm['paypal'] as Map?)?['payer_email'] ?? 'PayPal'}');
      case 'klarna':
        return ('klarna', 'Klarna');
      default:
        return ('card', '${pm['type']}');
    }
  }

  @override
  Future<Entitlement> refresh(Entitlement e) => _read(e.subscription, e.customer);

  @override
  Future<String> portal(Entitlement e, String returnUrl) async {
    final s = await _req('POST', '/billing_portal/sessions', {'customer': e.customer, 'return_url': returnUrl});
    return '${s['url']}';
  }

  @override
  Future<Entitlement> setCancel(Entitlement e, bool cancel) async {
    await _req('POST', '/subscriptions/${e.subscription}', {'cancel_at_period_end': '$cancel'});
    return _read(e.subscription, e.customer);
  }

  @override
  Future<Entitlement> withdraw(Entitlement e) async {
    final s = await _req('GET', '/subscriptions/${e.subscription}?expand[]=latest_invoice');
    final invoice = s['latest_invoice'] as Map?;
    // refund first: if that fails, the subscription still exists and a retry works
    // (nothing was paid during the free trial)
    final paid = (invoice?['amount_paid'] as num?) ?? 0;
    final intent = invoice?['payment_intent'] ?? invoice?['charge'];
    if (paid > 0) {
      if (intent == null) throw BillingError('Die Zahlung zur Erstattung wurde nicht gefunden.');
      await _req('POST', '/refunds', {(invoice?['payment_intent'] != null ? 'payment_intent' : 'charge'): '$intent'});
    }
    await _req('DELETE', '/subscriptions/${e.subscription}');
    return e.copyWith(status: 'canceled');
  }

  // Stripe-Signature: t=<unix>,v1=<hex hmac of "t.payload">; at most 5 minutes old
  static bool verifyWebhook(String payload, String header, String secret, {DateTime? now}) {
    final parts = <String, List<String>>{};
    for (final p in header.split(',')) {
      final i = p.indexOf('=');
      if (i > 0) parts.putIfAbsent(p.substring(0, i).trim(), () => []).add(p.substring(i + 1).trim());
    }
    final t = int.tryParse(parts['t']?.first ?? '');
    if (t == null) return false;
    final age = (now ?? DateTime.now()).difference(DateTime.fromMillisecondsSinceEpoch(t * 1000));
    if (age.abs() > const Duration(minutes: 5)) return false;
    final expected = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$t.$payload')).toString();
    return (parts['v1'] ?? const []).any((v) => _same(v, expected));
  }

  static bool _same(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

// Demo checkout: the same steps on pages of this server, never charges.
class DemoBilling implements Billing {
  final String serverUrl;
  DemoBilling(this.serverUrl);

  // session id -> what was ordered
  final _sessions = <String, ({String user, String plan, int trialDays, String returnUrl, String cancelUrl, bool paid})>{};

  @override
  String get mode => 'demo';

  ({String user, String plan, int trialDays, String returnUrl, String cancelUrl, bool paid})? session(String id) =>
      _sessions[id];

  void markPaid(String id) {
    final s = _sessions[id];
    if (s != null) {
      _sessions[id] = (
        user: s.user,
        plan: s.plan,
        trialDays: s.trialDays,
        returnUrl: s.returnUrl,
        cancelUrl: s.cancelUrl,
        paid: true
      );
    }
  }

  @override
  Future<String> checkout({
    required String user,
    required String email,
    required String plan,
    required int trialDays,
    required String returnUrl,
    required String cancelUrl,
    String? customer,
  }) async {
    final id = 'demo_cs_${DateTime.now().microsecondsSinceEpoch}';
    _sessions[id] =
        (user: user, plan: plan, trialDays: trialDays, returnUrl: returnUrl, cancelUrl: cancelUrl, paid: false);
    return '$serverUrl/plus/demo-checkout?session=$id';
  }

  @override
  Future<Entitlement?> fromSession(String sessionId) async {
    final s = _sessions[sessionId];
    if (s == null || !s.paid) return null;
    final now = DateTime.now();
    final trialEnds = now.add(Duration(days: s.trialDays));
    return Entitlement(
      plan: s.plan,
      status: s.trialDays > 0 ? 'trialing' : 'active',
      started: now,
      trialEnds: trialEnds,
      periodEnd: trialEnds,
      cancelAtPeriodEnd: false,
      method: 'card',
      methodDetail: 'Visa •••• 4242',
      customer: 'demo_cus_${s.user}',
      subscription: 'demo_sub_$sessionId',
      checked: now,
    );
  }

  @override
  Future<Entitlement> refresh(Entitlement e) async {
    final now = DateTime.now();
    if (e.cancelAtPeriodEnd && now.isAfter(e.periodEnd)) return e.copyWith(status: 'canceled');
    if (e.status == 'trialing' && now.isAfter(e.trialEnds)) return e.copyWith(status: 'active');
    return e.copyWith();
  }

  @override
  Future<String> portal(Entitlement e, String returnUrl) async =>
      '$serverUrl/plus/demo-portal?return=${Uri.encodeQueryComponent(returnUrl)}';

  @override
  Future<Entitlement> setCancel(Entitlement e, bool cancel) async => e.copyWith(cancelAtPeriodEnd: cancel);

  @override
  Future<Entitlement> withdraw(Entitlement e) async => e.copyWith(status: 'canceled');
}
