// Things in the bookings that cost money without anyone noticing: the same
// amount charged twice by the same merchant, and bank fees (account fees,
// overdraft interest, foreign card fees). Used for hints and by Buddy.
import '../models/transaction.dart';

class DoubleCharge {
  final Transaction first, second;
  const DoubleCharge(this.first, this.second);
  int get cents => second.amountCents;
  String get merchant => second.note ?? second.category;
}

class BankFee {
  final String kind; // konto, dispo, ausland, sonstige
  final int cents; // in the period
  final int count;
  const BankFee(this.kind, this.cents, this.count);
}

class Oddities {
  static String _key(String? note) =>
      (note ?? '').toLowerCase().replaceAll(RegExp(r'[^a-zäöüß]'), '').replaceAll(RegExp(r'(gmbh|ag|se|kg)$'), '');

  // the same merchant and amount twice within three days, in the last [days]
  static List<DoubleCharge> doubles(List<Transaction> tx, {DateTime? now, int days = 30}) {
    final today = now ?? DateTime.now();
    final recent = [
      for (final t in tx)
        if (!t.isIncome &&
            t.amountCents >= 500 &&
            t.category != 'Umbuchung' &&
            _key(t.note).length >= 3 &&
            today.difference(t.date).inDays <= days &&
            !t.date.isAfter(today))
          t
    ]..sort((a, b) => a.date.compareTo(b.date));
    final out = <DoubleCharge>[];
    final used = <String>{};
    for (var i = 0; i < recent.length; i++) {
      for (var j = i + 1; j < recent.length; j++) {
        final a = recent[i], b = recent[j];
        if (b.date.difference(a.date).inDays > 3) break;
        if (used.contains(a.id) || used.contains(b.id)) continue;
        if (a.amountCents == b.amountCents && _key(a.note) == _key(b.note)) {
          out.add(DoubleCharge(a, b));
          used
            ..add(a.id)
            ..add(b.id);
        }
      }
    }
    return out;
  }

  static final _fees = <String, RegExp>{
    'dispo': RegExp(r'dispo|überziehung|ueberziehung|sollzins|overdraft', caseSensitive: false),
    'ausland': RegExp(r'auslandseinsatz|fremdwährung|fremdwaehrung|währungsumrechnung|foreign (transaction|currency)',
        caseSensitive: false),
    'konto': RegExp(r'kontoführung|kontofuehrung|kontopaket|grundpreis|account fee|entgelt\s*konto|kartenentgelt|kartengebühr',
        caseSensitive: false),
    'sonstige': RegExp(r'\b(gebühr|entgelt|bankgebühr|fee)\b', caseSensitive: false),
  };

  // bank fees of the last [days], per kind
  static List<BankFee> fees(List<Transaction> tx, {DateTime? now, int days = 90}) {
    final today = now ?? DateTime.now();
    final sums = <String, (int, int)>{};
    for (final t in tx) {
      if (t.isIncome || today.difference(t.date).inDays > days || t.date.isAfter(today)) continue;
      final text = '${t.note ?? ''} ${t.category}';
      for (final e in _fees.entries) {
        if (e.value.hasMatch(text)) {
          final (c, n) = sums[e.key] ?? (0, 0);
          sums[e.key] = (c + t.amountCents, n + 1);
          break;
        }
      }
    }
    return [for (final e in sums.entries) BankFee(e.key, e.value.$1, e.value.$2)]
      ..sort((a, b) => b.cents.compareTo(a.cents));
  }

  // fees of [days] as a year
  static int yearly(List<BankFee> fees, {int days = 90}) =>
      (fees.fold<int>(0, (s, f) => s + f.cents) * 365 / days).round();
}
