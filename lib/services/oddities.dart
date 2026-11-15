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

// a direct debit that came back: the money is here again, the bill is not paid
class ReturnedDebit {
  final Transaction back; // the money coming back
  final Transaction? debit; // the original debit, when it is in the bookings
  const ReturnedDebit(this.back, this.debit);
  String get merchant => debit?.note ?? back.note ?? back.category;
  int get cents => back.amountCents;
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

  static final _returned = RegExp(
      r'r[üu]cklastschrift|r[üu]ckbelastung|lastschriftr[üu]ckgabe|r[üu]ckgabe lastschrift|retoure lastschrift|'
      r'sepa[\s-]?r[üu]ckgabe|returned debit|chargeback|r-transaktion',
      caseSensitive: false);

  // money back in the last [days] that the bank marks as a returned debit,
  // or that exactly reverses a debit of the same merchant within ten days
  static List<ReturnedDebit> returnedDebits(List<Transaction> tx, {DateTime? now, int days = 14}) {
    final today = now ?? DateTime.now();
    final out = <ReturnedDebit>[];
    for (final t in tx) {
      if (!t.isIncome || t.date.isAfter(today) || today.difference(t.date).inDays > days) continue;
      final marked = _returned.hasMatch('${t.note ?? ''} ${t.raw ?? ''}');
      Transaction? debit;
      for (final d in tx) {
        if (d.isIncome || d.amountCents != t.amountCents || d.date.isAfter(t.date)) continue;
        if (t.date.difference(d.date).inDays > 10) continue;
        final k = _key(d.note);
        if (k.length >= 3 && (_key(t.note).contains(k) || _key(t.raw).contains(k))) debit = d;
      }
      // a plain refund of a purchase is no returned debit: it needs the bank's word or a debit text
      final debitText = debit != null &&
          RegExp(r'lastschrift|mandat|sepa|direct debit', caseSensitive: false).hasMatch(debit.raw ?? '');
      final refund = RegExp(r'erstattung|refund|gutschrift|r[üu]ckzahlung|storno', caseSensitive: false)
          .hasMatch('${t.note ?? ''} ${t.raw ?? ''}');
      if (marked || (debitText && !refund)) out.add(ReturnedDebit(t, debit));
    }
    return out;
  }

  static final _dunning = RegExp(
      r'mahngeb[üu]hr|mahnung|mahnkosten|inkasso|zahlungserinnerung|s[äa]umniszuschlag|verzugszins|'
      r'collection agency|reminder fee|late fee',
      caseSensitive: false);
  static final _collector = RegExp(r'inkasso|collection agency|eos\b|creditreform|inf?oscore|riverty|pair finance|'
      r'coeo|intrum|lowell',
      caseSensitive: false);

  // fees for paying late, or money to a debt collector, in the last [days]
  static List<({Transaction tx, bool collector})> dunning(List<Transaction> tx, {DateTime? now, int days = 30}) {
    final today = now ?? DateTime.now();
    return [
      for (final t in tx)
        if (!t.isIncome && !t.date.isAfter(today) && today.difference(t.date).inDays <= days)
          if (_dunning.hasMatch('${t.note ?? ''} ${t.raw ?? ''}') || _collector.hasMatch('${t.note ?? ''} ${t.raw ?? ''}'))
            (tx: t, collector: _collector.hasMatch('${t.note ?? ''} ${t.raw ?? ''}'))
    ]..sort((a, b) => b.tx.date.compareTo(a.tx.date));
  }
}
