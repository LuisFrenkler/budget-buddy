// Checks the Stripe webhook signature verification against a known-good signature.
// Run: dart run tool/check_webhook_signature.dart
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:budget_buddy_backend/billing.dart';

void main() {
  const secret = 'whsec_test';
  const payload = '{"type":"customer.subscription.updated"}';
  final now = DateTime.now();
  final t = now.millisecondsSinceEpoch ~/ 1000;
  final sig = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$t.$payload')).toString();
  final checks = {
    'valid': StripeBilling.verifyWebhook(payload, 't=$t,v1=$sig', secret),
    'wrong secret rejected': !StripeBilling.verifyWebhook(payload, 't=$t,v1=$sig', 'whsec_other'),
    'changed payload rejected': !StripeBilling.verifyWebhook('$payload ', 't=$t,v1=$sig', secret),
    'old signature rejected': !StripeBilling.verifyWebhook(payload, 't=$t,v1=$sig', secret,
        now: now.add(const Duration(minutes: 6))),
    'missing header rejected': !StripeBilling.verifyWebhook(payload, '', secret),
  };
  checks.forEach((k, v) => print('${v ? 'ok  ' : 'FAIL'} $k'));
  if (checks.values.contains(false)) throw StateError('signature check failed');
}
