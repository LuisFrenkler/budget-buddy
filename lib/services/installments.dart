// Buy now, pay later: Klarna, PayPal in instalments, shop financing. Each
// one is small, together they are debt that runs every month. Found from
// the bank texts: the same amount to a financing provider in at least two
// months, the last one within six weeks.
import '../models/transaction.dart';
import '../utils/merchant.dart';

class Installment {
  final String provider;
  final String? shop;
  final int monthlyCents;
  final int paidCount;
  final DateTime last;
  const Installment(this.provider, this.shop, this.monthlyCents, this.paidCount, this.last);
}

class Installments {
  static final _providers = <String, RegExp>{
    'Klarna': RegExp(r'klarna', caseSensitive: false),
    'PayPal Ratenzahlung': RegExp(r'paypal.{0,30}(rate|später|spaeter|pay later|pay in|in 3|in 30)', caseSensitive: false),
    'Ratenkredit': RegExp(
        r'ratenkauf|ratenzahlung|finanzierung|easycredit|santander consumer|consors finanz|creditplus|targobank kredit|'
        r'cofidis|bank11|hanseatic',
        caseSensitive: false),
  };

  static List<Installment> detect(List<Transaction> tx, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final groups = <String, List<Transaction>>{};
    final provider = <String, String>{};
    for (final t in tx) {
      if (t.isIncome || t.date.isAfter(today) || today.difference(t.date).inDays > 150) continue;
      final text = '${t.note ?? ''} ${t.raw ?? ''}';
      final p = _providers.entries.where((e) => e.value.hasMatch(text)).firstOrNull;
      if (p == null) continue;
      final key = '${p.key}|${t.amountCents}|${Merchant.key(t.note ?? '')}';
      groups.putIfAbsent(key, () => []).add(t);
      provider[key] = p.key;
    }
    final out = <Installment>[];
    for (final e in groups.entries) {
      final g = e.value..sort((a, b) => a.date.compareTo(b.date));
      final months = {for (final t in g) t.date.year * 12 + t.date.month};
      if (months.length < 2 || today.difference(g.last.date).inDays > 45) continue;
      final name = g.last.note?.trim() ?? '';
      final shop = name.isEmpty || _providers[provider[e.key]]!.hasMatch(name) ? null : Merchant.tidy(name);
      out.add(Installment(provider[e.key]!, shop, g.last.amountCents, g.length, g.last.date));
    }
    out.sort((a, b) => b.monthlyCents.compareTo(a.monthlyCents));
    return out;
  }

  static int monthly(List<Installment> list) => list.fold(0, (s, i) => s + i.monthlyCents);
}
