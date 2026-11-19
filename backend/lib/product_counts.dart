// Anonymous product counts: how often each funnel step happened per UTC day,
// and for the agent's finds also per kind of find. A day, a name, a kind and a
// number, nothing else: no address, no device, no account, no amount.
import 'dart:convert';
import 'dart:io';

import 'json_store.dart';

class ProductCounts {
  final File file;
  ProductCounts(this.file);

  // what the agent finds: HintKind names in AheadAgent.moneyKinds (app), plus the contracts look
  static const moneyKinds = {
    'overdraft', 'stillCharging', 'priceUp', 'doubleCharge', 'subTip', 'bankFees', 'dunning', 'returnedDebit', 'contracts',
  };
  static const kinds = {'tax', ...moneyKinds};

  // a kind only belongs to a find, so the keys in the file stay a small fixed set
  static bool allows(String name, String? kind) => kind == null || (name.startsWith('find_') && kinds.contains(kind));

  static String day(DateTime d) => d.toUtc().toIso8601String().substring(0, 10);

  // day -> "name" or "name:kind" -> count
  late final Map<String, Map<String, int>> _days = _read();

  Map<String, Map<String, int>> _read() {
    if (!file.existsSync()) return {};
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return {
      for (final d in data.entries)
        d.key: {for (final c in (d.value as Map).entries) '${c.key}': (c.value as num).toInt()}
    };
  }

  // counts the name, and the name with its kind when there is one
  Future<void> add(String name, {String? kind, DateTime? now}) async {
    final counts = _days[day(now ?? DateTime.now())] ??= {};
    counts.update(name, (n) => n + 1, ifAbsent: () => 1);
    if (kind != null) counts.update('$name:$kind', (n) => n + 1, ifAbsent: () => 1);
    // shortcut: the whole file is rewritten per event (about 1 KB per day of history), move to an append-only log once that shows up in timings.
    await writeJsonAtomic(file, _days);
  }

  // the last [days] days, today included: counts per day, per name, per name and kind, and the rates of the agent loop
  Map<String, dynamic> summary({int days = 30, DateTime? now}) {
    final from = day((now ?? DateTime.now()).toUtc().subtract(Duration(days: days - 1)));
    final byDay = {
      for (final d in _days.keys.toList()..sort())
        if (d.compareTo(from) >= 0) d: _days[d]!
    };
    final byName = <String, int>{};
    final byKind = <String, Map<String, int>>{};
    for (final counts in byDay.values) {
      counts.forEach((key, n) {
        final i = key.indexOf(':');
        final into = i < 0 ? byName : byKind[key.substring(0, i)] ??= {};
        into.update(i < 0 ? key : key.substring(i + 1), (v) => v + n, ifAbsent: () => n);
      });
    }
    int count(String name, [Iterable<String>? of]) =>
        of == null ? byName[name] ?? 0 : of.fold(0, (sum, k) => sum + (byKind[name]?[k] ?? 0));
    Map<String, dynamic> rate(int yes, int shown) =>
        {'yes': yes, 'shown': shown, 'rate': shown == 0 ? null : yes / shown};
    // finds counted without a kind (an older app) only allow the rough rate against every find shown
    final kinded = count('find_shown', kinds) > 0;
    Map<String, dynamic> yes(String name, Iterable<String> of) => kinded
        ? rate(count(name, of), count('find_shown', of))
        : rate(count(name), count('find_shown'));
    return {
      'days': days,
      'from': from,
      'byDay': byDay,
      'byName': byName,
      'byKind': byKind,
      'rates': {
        'yesTax': yes('find_yes_tax', const ['tax']),
        'yesMoney': yes('find_yes_money', moneyKinds),
        'yesByKind': {
          for (final k in kinds)
            if (count('find_shown', [k]) > 0)
              k: rate(count('find_yes_tax', [k]) + count('find_yes_money', [k]), count('find_shown', [k]))
        },
        'later': rate(count('find_later'), count('find_shown')),
      },
    };
  }
}
