// BudgetBuddy Plus: who has it and how much of the free tier is used.
//
// Free: 5 AI questions and 3 receipt scans per month, 1 savings goal.
// Plus: everything without limits, 7 days free, then monthly or yearly.
//
// The subscription (plan, payment method, trial, renewal, cancellation) is
// kept in the settings box.
//
// Signed in with the server reachable, the purchase runs on the server
// (Stripe Checkout, see backend/lib/billing.dart): the app never sees payment
// details, and the server's copy decides who has Plus ("managed"). Without a
// server the checkout runs in a clearly labelled local test mode that never
// charges anything. The iPhone and Android apps buy through the App Store and
// Google Play (store_purchases.dart), also checked by the server.
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'account_service.dart';
import 'backend_service.dart';
import 'store_purchases.dart';

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
  final bool managed; // bought through the server; changes go through it
  // the end of the running period as Stripe or the store reports it; wins
  // over the local calculation, which can't know about plan changes or retries
  final DateTime? serverPeriodEnd;

  const Subscription({
    required this.plan,
    required this.method,
    required this.methodDetail,
    required this.started,
    required this.trialEnds,
    this.endsAt,
    this.managed = false,
    this.serverPeriodEnd,
  });

  bool get cancelled => endsAt != null;

  // bought in the App Store or Google Play: managed there, not here
  bool get fromStore => managed && (method == PayMethod.appStore || method == PayMethod.googlePlay);

  bool inTrial(DateTime now) => now.isBefore(trialEnds);

  int get priceCents => plan == PlusPlan.yearly ? PlusService.yearlyCents : PlusService.monthlyCents;

  // the n-th payment date after the trial, counted from the trial's day, so
  // a start on the 31st pays on the 30th or 28th in short months and on the
  // 31st again after (adding one month at a time would drift to the 3rd)
  DateTime _payment(int n) {
    final months = plan == PlusPlan.yearly ? 12 * n : n;
    final t = trialEnds;
    final last = DateTime(t.year, t.month + months + 1, 0).day;
    return DateTime(t.year, t.month + months, t.day > last ? last : t.day, t.hour, t.minute);
  }

  // the next payment date (the end of the current period)
  DateTime periodEnd(DateTime now) {
    final server = serverPeriodEnd;
    if (server != null && server.isAfter(now)) return server;
    var n = 0;
    while (!_payment(n).isAfter(now)) {
      n++;
    }
    return _payment(n);
  }

  // every payment since the trial ended, newest first
  List<Invoice> invoices(DateTime now) {
    final list = <Invoice>[];
    // after a cancellation the date at [endsAt] is not charged any more
    for (var n = 0; !_payment(n).isAfter(now) && (endsAt == null || _payment(n).isBefore(endsAt!)); n++) {
      list.add(Invoice(_payment(n), priceCents, plan));
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
        managed: managed,
        serverPeriodEnd: serverPeriodEnd,
      );

  Map<String, dynamic> toMap() => {
        'plan': plan.name,
        'method': method.name,
        'methodDetail': methodDetail,
        'started': started.toIso8601String(),
        'trialEnds': trialEnds.toIso8601String(),
        if (endsAt != null) 'endsAt': endsAt!.toIso8601String(),
        if (managed) 'managed': true,
        if (serverPeriodEnd != null) 'periodEnd': serverPeriodEnd!.toIso8601String(),
      };

  static Subscription fromMap(Map m) => Subscription(
        plan: PlusPlan.values.byName(m['plan'] as String),
        method: PayMethod.values.byName(m['method'] as String),
        methodDetail: m['methodDetail'] as String? ?? '',
        started: DateTime.parse(m['started'] as String),
        trialEnds: DateTime.parse(m['trialEnds'] as String),
        endsAt: m['endsAt'] == null ? null : DateTime.parse(m['endsAt'] as String),
        managed: m['managed'] == true,
        serverPeriodEnd: m['periodEnd'] == null ? null : DateTime.tryParse('${m['periodEnd']}'),
      );

  // the server's entitlement (backend/lib/billing.dart) as a subscription
  static Subscription fromServer(Map e) => Subscription(
        plan: e['plan'] == 'yearly' ? PlusPlan.yearly : PlusPlan.monthly,
        method: PayMethod.values.asNameMap()['${e['method']}'] ?? PayMethod.card,
        methodDetail: '${e['methodDetail'] ?? ''}',
        started: DateTime.parse('${e['started']}'),
        trialEnds: DateTime.parse('${e['trialEnds']}'),
        endsAt: e['cancelAtPeriodEnd'] == true ? DateTime.parse('${e['periodEnd']}') : null,
        managed: true,
        serverPeriodEnd: DateTime.tryParse('${e['periodEnd']}'),
      );
}

class PlusService {
  static const freeAiQuestions = 5;
  static const freeReceiptScans = 3;
  static const freeGoals = 1;
  static const trialDays = 7;

  static const monthlyCents = 499;
  static const yearlyCents = 3999;

  // monthly and yearly price as shown on the paywall (the same in the stores)
  static const monthlyPrice = '4,99 €';
  static const yearlyPrice = '39,99 €';

  // in the apps the store's own price, as soon as it is loaded
  static String price(PlusPlan plan) =>
      StorePurchases.prices.value[plan] ?? (plan == PlusPlan.yearly ? yearlyPrice : monthlyPrice);
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

  // --- server (signed in) ---

  // takes over the server's copy: it decides whether Plus exists for this account
  static Future<void> applyServer(Map<String, dynamic>? entitlement) async {
    if (entitlement != null) {
      await _store(Subscription.fromServer(entitlement));
    } else if (AccountService.token != null) {
      // signed in: server is source of truth — clear local/debug and managed alike
      // (store purchases stay via applyStore / plusStore id)
      if (subscription.value?.fromStore != true) await _store(null);
    }
  }

  // a store purchase as the server checked it (null: not active). The store's
  // id stays on the device, so it is checked again later, and a guest's Plus
  // moves to the account at sign-in.
  static Future<void> applyStore(Map<String, dynamic>? entitlement,
      {required String platform, required String id}) async {
    if (entitlement != null) {
      await _box.put('plusStore', {'platform': platform, 'id': id});
      await _store(Subscription.fromServer(entitlement));
    } else if ((_box.get('plusStore') as Map?)?['id'] == id) {
      await _box.delete('plusStore');
      if (subscription.value?.fromStore == true) await _store(null);
    }
  }

  // last sync outcome for UI (null = not tried / ok, text = problem)
  static final syncError = ValueNotifier<String?>(null);

  // asks the server what this device and account have; false when it cannot be asked
  static Future<bool> syncWithServer({bool fresh = false}) async {
    final store = _box.get('plusStore') as Map?;
    if (AccountService.token == null && store == null) return false;
    try {
      if (store != null) {
        // checked with the store again; signed in, this also binds it to the account
        final platform = '${store['platform']}', id = '${store['id']}';
        await applyStore(await BackendService.plusStore(platform, id), platform: platform, id: id);
      }
      if (AccountService.token != null) await applyServer(await BackendService.plusStatus(fresh: fresh));
      syncError.value = null;
      return true;
    } catch (_) {
      syncError.value = 'Plus-Status konnte nicht geprüft werden. Tippe hier zum erneuten Versuchen.';
      return false;
    }
  }

  // signing in brings a bought Plus along, signing out takes it away
  static void watchAccount() {
    AccountService.current.addListener(() {
      if (AccountService.current.value != null) {
        syncWithServer();
      } else if (subscription.value?.managed == true && subscription.value?.fromStore != true) {
        // a store purchase belongs to the Apple ID or Google account, not to ours
        _store(null);
      }
    });
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
    if (sub?.fromStore == true) return StorePurchases.manage();
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
    if (sub?.fromStore == true) return StorePurchases.manage();
    if (sub?.managed == true) return applyServer(await BackendService.plusCancel(true));
    if (sub != null) await _store(sub.copyWith(endsAt: sub.periodEnd(now ?? DateTime.now())));
  }

  static Future<void> resume() async {
    final sub = subscription.value;
    if (sub?.fromStore == true) return StorePurchases.manage();
    if (sub?.managed == true) return applyServer(await BackendService.plusCancel(false));
    if (sub != null) await _store(sub.copyWith(resume: true));
  }

  // the 14-day right of withdrawal; ends Plus right away
  static bool canWithdraw(Subscription sub, {DateTime? now}) =>
      (now ?? DateTime.now()).difference(sub.started) < const Duration(days: 14);

  static Future<void> withdraw() async {
    // the store decides about refunds of its purchases
    if (subscription.value?.fromStore == true) return StorePurchases.requestRefund();
    if (subscription.value?.managed == true) await BackendService.plusWithdraw();
    await end();
  }

  // "Käufe wiederherstellen": asks the store (in the apps) and the server,
  // otherwise reloads what this device knows
  static Future<bool> restore() async {
    if (StorePurchases.supported) await StorePurchases.restore();
    if (!await syncWithServer(fresh: true)) load();
    return active.value;
  }

  // for tests and the app reset
  static Future<void> end() async {
    await _box.delete('plusStore');
    await _store(null);
  }

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
