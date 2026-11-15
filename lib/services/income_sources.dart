// Where the money comes from, and what of it comes every month: salary,
// Kindergeld, BAföG, a side job, rent from a flatmate. One-offs (a bonus, a
// tax refund, a gift) are listed apart, so the month forecast does not count
// on them. A source is regular when it paid in at least two of the last three
// complete months; its monthly amount is the middle of those months, so a
// side job that pays a little more or less still counts as what it usually is.
import '../models/transaction.dart';
import '../utils/merchant.dart';

class IncomeSource {
  final String name;
  final String kind; // gehalt, kindergeld, bafoeg, nebenjob, unterhalt, wohngeld, sonstiges
  final int monthlyCents; // usual per month (regular) or the sum (one-off)
  final int months; // complete months of the last three it paid in
  final bool regular;
  final DateTime last;
  const IncomeSource(this.name, this.kind, this.monthlyCents, this.months, this.regular, this.last);
}

class IncomeSources {
  static final _kinds = <String, RegExp>{
    'kindergeld': RegExp(r'kindergeld|familienkasse', caseSensitive: false),
    'bafoeg': RegExp(r'baf[öo]e?g|studierendenwerk|studentenwerk|ausbildungsf[öo]rderung', caseSensitive: false),
    'wohngeld': RegExp(r'wohngeld', caseSensitive: false),
    'unterhalt': RegExp(r'unterhalt', caseSensitive: false),
    'nebenjob': RegExp(r'minijob|nebenjob|aushilfe|werkstudent|honorar|freelance', caseSensitive: false),
  };

  static String _kind(Transaction t) {
    final text = '${t.note ?? ''} ${t.raw ?? ''} ${t.category}';
    for (final e in _kinds.entries) {
      if (e.value.hasMatch(text)) return e.key;
    }
    if (t.category == 'Nebenjob') return 'nebenjob';
    if (t.category == 'Gehalt') return 'gehalt';
    return 'sonstiges';
  }

  static List<IncomeSource> detect(List<Transaction> tx, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final months = [for (var m = 1; m <= 3; m++) DateTime(today.year, today.month - m)];
    final from = months.last;
    final groups = <String, List<Transaction>>{};
    for (final t in tx) {
      if (!t.isEarning || t.category == 'Umbuchung' || t.date.isBefore(from) || t.date.isAfter(today)) continue;
      final kind = _kind(t);
      // a salary keeps its source even when the payer's text changes a little
      final key = kind == 'sonstiges' || kind == 'nebenjob' ? '$kind|${Merchant.key(t.note ?? t.category)}' : kind;
      groups.putIfAbsent(key, () => []).add(t);
    }
    final out = <IncomeSource>[];
    for (final g in groups.values) {
      g.sort((a, b) => a.date.compareTo(b.date));
      final perMonth = [
        for (final m in months)
          g.where((t) => t.date.year == m.year && t.date.month == m.month).fold<int>(0, (s, t) => s + t.amountCents)
      ];
      final paid = perMonth.where((c) => c > 0).toList()..sort();
      final regular = paid.length >= 2;
      final name = Merchant.tidy(g.last.note ?? '').isEmpty ? g.last.category : Merchant.tidy(g.last.note!);
      out.add(IncomeSource(
        name,
        _kind(g.last),
        regular ? paid[(paid.length - 1) ~/ 2] : g.fold<int>(0, (s, t) => s + t.amountCents),
        paid.length,
        regular,
        g.last.date,
      ));
    }
    out.sort((a, b) => b.monthlyCents.compareTo(a.monthlyCents));
    return out;
  }

  // what comes in every month, from the regular sources only
  static int regularMonthly(List<IncomeSource> s) =>
      s.where((x) => x.regular).fold<int>(0, (sum, x) => sum + x.monthlyCents);
}
