// Product counters for the seed dashboard.
//
// A line is "YYYY-MM-DD name" and nothing else. No email, name, question,
// answer, amount, IBAN, or account id. The app sets [send] to POST /events,
// which takes the name only (the server stamps its own day).
//
// shortcut: once per install, not per account; count per account once the funnel needs it.
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class ProductEvents {
  static const waitlistSignup = 'waitlist_signup';
  static const activated = 'activated';
  static const d1 = 'd1';
  static const d7 = 'd7';
  static const trialStart = 'trial_start';
  static const paid = 'paid';
  static const bankConnect = 'bank_connect';
  // the tax funnel: check, filed, assessed, and how close the estimate was
  static const refundCheck = 'refund_check';
  // where the check came from: the start screen or inside the app (the MCP tool counts on the server)
  static const refundCheckStart = 'refund_check_start';
  static const refundCheckApp = 'refund_check_app';
  // the same notice against an estimate without bank, receipts or certificate
  static const controlWithin10 = 'control_within_10';
  static const controlWithin25 = 'control_within_25';
  static const controlOff = 'control_off';
  static const taxFiled = 'tax_filed';
  static const assessment = 'assessment';
  static const estimateWithin10 = 'estimate_within_10';
  static const estimateWithin25 = 'estimate_within_25';
  static const estimateOff = 'estimate_off';
  // the agent loop: a find shown, a yes to it, put away, money really back
  static const findShown = 'find_shown';
  static const findYesTax = 'find_yes_tax';
  static const findYesMoney = 'find_yes_money';
  static const findLater = 'find_later';
  static const moneyRecovered = 'money_recovered';

  static const names = {
    waitlistSignup,
    activated,
    d1,
    d7,
    trialStart,
    paid,
    bankConnect,
    refundCheck,
    refundCheckStart,
    refundCheckApp,
    controlWithin10,
    controlWithin25,
    controlOff,
    taxFiled,
    assessment,
    estimateWithin10,
    estimateWithin25,
    estimateOff,
    findShown,
    findYesTax,
    findYesMoney,
    findLater,
    moneyRecovered,
  };

  // "1.234,50 €" and "€4.99". The privacy mask "•••••• €" has no digit.
  static final _money = RegExp(r'€\s*\d[\d.,]*|\d[\d.,]*\s*€');

  // shortcut: any non-zero euro amount counts, including a demo ledger; require the user's own book once you have 50 activations.
  static bool hasFigure(String text) {
    for (final m in _money.allMatches(text)) {
      if (RegExp(r'[1-9]').hasMatch(m.group(0)!)) return true;
    }
    return false;
  }

  /// Last lines, for tests and a local glance. Capped.
  static final log = <String>[];

  /// Set this to POST. Null means do nothing remote.
  static Future<void> Function(String name, String day)? send;

  static final _mem = <String, String>{};

  @visibleForTesting
  static void reset() {
    log.clear();
    _mem.clear();
    send = null;
  }

  static Future<void> track(String name, {DateTime? now}) async {
    if (!names.contains(name)) return;
    if (_flag(name) != null) return;
    final day = _day(now ?? DateTime.now());
    await _setFlag(name, day);
    if (name == activated) await _setFlag('anchor', day);
    final line = '$day $name';
    log.add(line);
    if (log.length > 50) log.removeAt(0);
    debugPrint('product_event $line');
    await _remember(line);
    final remote = send;
    if (remote == null) return;
    try {
      await remote(name, day);
    } catch (_) {}
  }

  /// Call with the finished Buddy answer, not a Plus-price help text.
  static Future<void> noteAnswer(String text, {DateTime? now}) async {
    if (_flag(activated) != null) return;
    if (!hasFigure(text)) return;
    await track(activated, now: now);
  }

  /// App open. D1 and D7 are calendar days after the activation day.
  static Future<void> noteOpen({DateTime? now}) async {
    final anchor = _flag('anchor');
    if (anchor == null) return;
    final day = now ?? DateTime.now();
    final diff = _daysAfter(anchor, day);
    if (diff == 1) await track(d1, now: day);
    if (diff == 7) await track(d7, now: day);
  }

  /// [trial] while the 7 days are still running. [charged] only after a
  /// payment date has passed. A trial is not [charged].
  static Future<void> notePlus({required bool trial, required bool charged, DateTime? now}) async {
    if (trial) await track(trialStart, now: now);
    if (charged) await track(paid, now: now);
  }

  static String? _flag(String name) {
    final mem = _mem[name];
    if (mem != null) return mem;
    if (!Hive.isBoxOpen('settings')) return null;
    final v = Hive.box('settings').get('pe_$name');
    if (v is! String) return null;
    _mem[name] = v;
    return v;
  }

  static Future<void> _setFlag(String name, String day) async {
    _mem[name] = day;
    if (!Hive.isBoxOpen('settings')) return;
    try {
      await Hive.box('settings').put('pe_$name', day);
    } catch (_) {}
  }

  static Future<void> _remember(String line) async {
    if (!Hive.isBoxOpen('settings')) return;
    try {
      final box = Hive.box('settings');
      final prev = [for (final e in (box.get('pe_log') as List?) ?? const []) '$e'];
      prev.add(line);
      if (prev.length > 50) prev.removeRange(0, prev.length - 50);
      await box.put('pe_log', prev);
    } catch (_) {}
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // UTC midnights, so a DST Sunday still counts as one day.
  static int _daysAfter(String anchor, DateTime now) {
    final p = anchor.split('-');
    if (p.length != 3) return -1;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return -1;
    final start = DateTime.utc(y, m, d);
    final today = DateTime.utc(now.year, now.month, now.day);
    return today.difference(start).inDays;
  }
}
