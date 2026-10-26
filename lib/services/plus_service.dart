// BudgetBuddy Plus: who has it and how much of the free tier is used.
//
// Free: 5 AI questions and 3 receipt scans per month, 1 savings goal.
// Plus: everything without limits, 7 days free, then monthly or yearly.
//
// The subscription (plan, payment method, trial, renewal, cancellation) is
// kept in the settings box. Payments are not connected yet: the checkout runs
// in a clearly labelled test mode and never charges anything. In the store
// builds the purchase goes through App Store / Google Play (e.g. RevenueCat),
// on the web through a payment provider such as Stripe.
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

enum PlusFeature { aiQuestion, receiptScan, goal }

enum PlusPlan { monthly, yearly }

enum PayMethod { appStore, googlePlay, applePay, googlePay, paypal, card, sepa, klarna }

extension PayMethodLabel on PayMethod {
  String get label => switch (this) {
        PayMethod.appStore => 'App Store',
        PayMethod.googlePlay => 'Google Play',
        PayMethod.applePay => 'Apple Pay',
        PayMethod.googlePay => 'Google Pay',
        PayMethod.paypal => 'PayPal',
        PayMethod.card => 'Kredit- oder Debitkarte',
        PayMethod.sepa => 'SEPA-Lastschrift',
        PayMethod.klarna => 'Klarna',
      };
}

class Invoice {
  final DateTime date;
  final int cents;
  final PlusPlan plan;
  const Invoice(this.date, this.cents, this.plan);

  String get number =>
      'BB-${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
}

class Subscription {
  final PlusPlan plan;
  final PayMethod method;
  final String methodDetail; // e.g. "Visa •••• 4242", the PayPal address or the masked IBAN
  final DateTime started;
  final DateTime trialEnds;
  final DateTime? endsAt; // set when cancelled: access runs until then

  const Subscription({
    required this.plan,
    required this.method,
    required this.methodDetail,
    required this.started,
    required this.trialEnds,
    this.endsAt,
  });

  bool get cancelled => endsAt != null;

  bool inTrial(DateTime now) => now.isBefore(trialEnds);

  int get priceCents => plan == PlusPlan.yearly ? PlusService.yearlyCents : PlusService.monthlyCents;

  DateTime _step(DateTime d) =>
      plan == PlusPlan.yearly ? DateTime(d.year + 1, d.month, d.day) : DateTime(d.year, d.month + 1, d.day);

  // the next payment date (the end of the current period)
  DateTime periodEnd(DateTime now) {
    var d = trialEnds;
    while (!d.isAfter(now)) {
      d = _step(d);
    }
    return d;
  }

  // every payment since the trial ended, newest first
  List<Invoice> invoices(DateTime now) {
    final list = <Invoice>[];
    var d = trialEnds;
    // after a cancellation the date at [endsAt] is not charged any more
    while (!d.isAfter(now) && (endsAt == null || d.isBefore(endsAt!))) {
      list.add(Invoice(d, priceCents, plan));
      d = _step(d);
    }
    return list.reversed.toList();
  }

  bool activeAt(DateTime now) => endsAt == null || now.isBefore(endsAt!);

  String get methodText => methodDetail.isEmpty ? method.label : methodDetail;

  Subscription copyWith({
    PlusPlan? plan,
    PayMethod? method,
    String? methodDetail,
    DateTime? trialEnds,
    DateTime? endsAt,
    bool resume = false,
  }) =>
      Subscription(
        plan: plan ?? this.plan,
        method: method ?? this.method,
        methodDetail: methodDetail ?? this.methodDetail,
        started: started,
        trialEnds: trialEnds ?? this.trialEnds,
        endsAt: resume ? null : endsAt ?? this.endsAt,
      );

  Map<String, dynamic> toMap() => {
        'plan': plan.name,
        'method': method.name,
        'methodDetail': methodDetail,
        'started': started.toIso8601String(),
        'trialEnds': trialEnds.toIso8601String(),
        if (endsAt != null) 'endsAt': endsAt!.toIso8601String(),
      };

  static Subscription fromMap(Map m) => Subscription(
        plan: PlusPlan.values.byName(m['plan'] as String),
        method: PayMethod.values.byName(m['method'] as String),
        methodDetail: m['methodDetail'] as String? ?? '',
        started: DateTime.parse(m['started'] as String),
        trialEnds: DateTime.parse(m['trialEnds'] as String),
        endsAt: m['endsAt'] == null ? null : DateTime.parse(m['endsAt'] as String),
      );
}

class PlusService {
  static const freeAiQuestions = 5;
  static const freeReceiptScans = 3;
  static const freeGoals = 1;
  static const trialDays = 7;

  static const monthlyCents = 499;
  static const yearlyCents = 3999;

  // monthly and yearly price as shown on the paywall
  static const monthlyPrice = '4,99 €';
  static const yearlyPrice = '39,99 €';
  static const yearlyPerMonth = '3,33 €';

  // codes for creators and friends: extra free days on top of the trial
  static const promoCodes = {'BUDDY30': 30, 'FREUND': 30, 'CREATOR60': 60, 'START14': 14};

  static Box get _box => Hive.box('settings');

  // notifiers so badges, limits and the subscription page update everywhere at once
  static final active = ValueNotifier<bool>(false);
  static final subscription = ValueNotifier<Subscription?>(null);

  static void load({DateTime? now}) {
    final raw = _box.get('plusSub') as Map?;
    Subscription? sub;
    if (raw != null) {
      try {
        sub = Subscription.fromMap(raw);
      } catch (_) {}
    }
    // a cancelled plan that has run out is gone
    if (sub != null && !sub.activeAt(now ?? DateTime.now())) {
      sub = null;
      _box.delete('plusSub');
    }
    subscription.value = sub;
    active.value = sub != null;
  }

  static Future<void> _store(Subscription? sub) async {
    if (sub == null) {
      await _box.delete('plusSub');
    } else {
      await _box.put('plusSub', sub.toMap());
    }
    subscription.value = sub;
    active.value = sub != null;
  }

  // days added by a promo code, or null for an unknown code
  static int? promoDays(String code) => promoCodes[code.trim().toUpperCase()];

  static Future<Subscription> start({
    required PlusPlan plan,
    required PayMethod method,
    String methodDetail = '',
    int extraDays = 0,
    DateTime? now,
  }) async {
    final today = now ?? DateTime.now();
    final sub = Subscription(
      plan: plan,
      method: method,
      methodDetail: methodDetail,
      started: today,
      trialEnds: today.add(Duration(days: trialDays + extraDays)),
    );
    await _store(sub);
    return sub;
  }

  static Future<void> changePlan(PlusPlan plan) async {
    final sub = subscription.value;
    if (sub != null) await _store(sub.copyWith(plan: plan));
  }

  static Future<void> changeMethod(PayMethod method, String detail) async {
    final sub = subscription.value;
    if (sub != null) await _store(sub.copyWith(method: method, methodDetail: detail));
  }

  // free days count from the end of the trial or the paid period
  static Future<bool> redeem(String code, {DateTime? now}) async {
    final days = promoDays(code);
    final sub = subscription.value;
    if (days == null || sub == null) return false;
    final today = now ?? DateTime.now();
    final base = sub.inTrial(today) ? sub.trialEnds : sub.periodEnd(today);
    await _store(sub.copyWith(trialEnds: base.add(Duration(days: days))));
    return true;
  }

  // access stays until the end of the period that is already paid (or the trial)
  static Future<void> cancel({DateTime? now}) async {
    final sub = subscription.value;
    if (sub != null) await _store(sub.copyWith(endsAt: sub.periodEnd(now ?? DateTime.now())));
  }

  static Future<void> resume() async {
    final sub = subscription.value;
    if (sub != null) await _store(sub.copyWith(resume: true));
  }

  // the 14-day right of withdrawal; ends Plus right away
  static bool canWithdraw(Subscription sub, {DateTime? now}) =>
      (now ?? DateTime.now()).difference(sub.started) < const Duration(days: 14);

  static Future<void> withdraw() => end();

  // "Käufe wiederherstellen": in test mode there is no store to ask, so this
  // only reloads what this device knows
  static bool restore() {
    load();
    return active.value;
  }

  // for tests and the app reset
  static Future<void> end() => _store(null);

  // a quick switch used by tests
  static Future<void> activateTest() =>
      start(plan: PlusPlan.yearly, method: kIsWeb ? PayMethod.card : PayMethod.appStore);
  static Future<void> cancelTest() => end();

  static String _monthKey(DateTime now) => '${now.year}-${now.month}';

  static String _counterKey(PlusFeature f) => 'usage_${f.name}';

  // how often a feature was used this month
  static int used(PlusFeature f, {DateTime? now}) {
    final raw = _box.get(_counterKey(f)) as Map?;
    if (raw == null || raw['month'] != _monthKey(now ?? DateTime.now())) return 0;
    return (raw['count'] as num).toInt();
  }

  static int limit(PlusFeature f) => switch (f) {
        PlusFeature.aiQuestion => freeAiQuestions,
        PlusFeature.receiptScan => freeReceiptScans,
        PlusFeature.goal => freeGoals,
      };

  // left in the free tier this month (goals: in total, counted by the caller)
  static int left(PlusFeature f, {DateTime? now}) => (limit(f) - used(f, now: now)).clamp(0, limit(f));

  static bool allowed(PlusFeature f, {int current = 0, DateTime? now}) {
    if (active.value) return true;
    if (f == PlusFeature.goal) return current < freeGoals;
    return used(f, now: now) < limit(f);
  }

  static Future<void> count(PlusFeature f, {DateTime? now}) async {
    if (active.value) return;
    final today = now ?? DateTime.now();
    await _box.put(_counterKey(f), {'month': _monthKey(today), 'count': used(f, now: today) + 1});
  }
}

// Checks for the checkout forms.
class PaymentChecks {
  static String digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  // Luhn check for card numbers
  static bool cardNumber(String input) {
    final d = digits(input);
    if (d.length < 13 || d.length > 19) return false;
    var sum = 0;
    for (var i = 0; i < d.length; i++) {
      var n = int.parse(d[d.length - 1 - i]);
      if (i.isOdd) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
    }
    return sum % 10 == 0;
  }

  static String cardBrand(String input) {
    final d = digits(input);
    if (d.startsWith('4')) return 'Visa';
    if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(d)) return 'Mastercard';
    if (RegExp(r'^3[47]').hasMatch(d)) return 'Amex';
    return 'Karte';
  }

  // MM/JJ, not in the past
  static bool expiry(String input, {DateTime? now}) {
    final m = RegExp(r'^(\d{2})\s*/\s*(\d{2})$').firstMatch(input.trim());
    if (m == null) return false;
    final month = int.parse(m.group(1)!);
    final year = 2000 + int.parse(m.group(2)!);
    if (month < 1 || month > 12) return false;
    final today = now ?? DateTime.now();
    return DateTime(year, month + 1).isAfter(DateTime(today.year, today.month));
  }

  static bool cvc(String input) => RegExp(r'^\d{3,4}$').hasMatch(input.trim());

  // ISO 13616 mod-97 check
  static bool iban(String input) {
    final s = input.replaceAll(' ', '').toUpperCase();
    if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$').hasMatch(s)) return false;
    if (s.startsWith('DE') && s.length != 22) return false;
    final moved = s.substring(4) + s.substring(0, 4);
    var rest = 0;
    for (final ch in moved.codeUnits) {
      final v = ch >= 65 ? '${ch - 55}' : String.fromCharCode(ch);
      for (final c in v.codeUnits) {
        rest = (rest * 10 + (c - 48)) % 97;
      }
    }
    return rest == 1;
  }

  static bool email(String input) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(input.trim());

  // "DE89 •••• 3000" for display
  static String maskIban(String input) {
    final s = input.replaceAll(' ', '').toUpperCase();
    return '${s.substring(0, 4)} •••• ${s.substring(s.length - 4)}';
  }
}
