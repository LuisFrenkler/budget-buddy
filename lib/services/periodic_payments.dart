// Payments that do not come every month: the car insurance once a year, the
// Rundfunkbeitrag every quarter, the ADAC or the BahnCard. They hit the
// account all at once, so Buddy puts a little aside every month for them.
// Found from the bookings: the same merchant with a quarter, half a year or
// a year between payments, or (for a first year) a known yearly kind.
import '../models/transaction.dart';
import '../utils/merchant.dart';

class PeriodicPayment {
  final String name;
  final int cents;
  final int everyMonths; // 3, 6 or 12
  final DateTime last;
  const PeriodicPayment(this.name, this.cents, this.everyMonths, this.last);

  DateTime get next => DateTime(last.year, last.month + everyMonths, last.day);
  int get monthlyCents => (cents / everyMonths).ceil();
}

class PeriodicPayments {
  // usually paid once a year (or a quarter for the Rundfunkbeitrag)
  static final _yearly = RegExp(
      r'kfz|autoversicherung|haftpflicht|hausrat|adac|bahncard|amazon prime|jahresbeitrag|jahresabo|'
      r'kfz-steuer|kraftfahrzeugsteuer|hauptzollamt|mitgliedsbeitrag|domain|icloud jahr',
      caseSensitive: false);
  static final _quarterly = RegExp(r'rundfunk|beitragsservice|ard zdf|gez', caseSensitive: false);

  static List<PeriodicPayment> detect(List<Transaction> tx, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final groups = <String, List<Transaction>>{};
    for (final t in tx) {
      if (t.isIncome || t.category == 'Umbuchung' || t.amountCents < 2000 || t.date.isAfter(today)) continue;
      if (today.difference(t.date).inDays > 400) continue;
      final key = Merchant.key(t.note ?? '');
      if (key.length < 3) continue;
      groups.putIfAbsent(key, () => []).add(t);
    }
    final out = <PeriodicPayment>[];
    for (final g in groups.values) {
      g.sort((a, b) => a.date.compareTo(b.date));
      final last = g.last;
      final name = Merchant.tidy(last.note ?? '');
      int? every;
      if (g.length >= 2) {
        final gap = last.date.difference(g[g.length - 2].date).inDays;
        if (gap >= 80 && gap <= 100) every = 3;
        if (gap >= 170 && gap <= 195) every = 6;
        if (gap >= 350 && gap <= 380) every = 12;
        // monthly or irregular: not this kind
        if (every == null) continue;
      } else {
        final text = '${last.note ?? ''} ${last.raw ?? ''}';
        if (_quarterly.hasMatch(text)) {
          every = 3;
        } else if (_yearly.hasMatch(text)) {
          every = 12;
        } else {
          continue;
        }
      }
      final p = PeriodicPayment(name.isEmpty ? last.category : name, last.amountCents, every, last.date);
      // long past due without a new payment: probably ended
      if (today.difference(p.next).inDays > 45) continue;
      out.add(p);
    }
    out.sort((a, b) => a.next.compareTo(b.next));
    return out;
  }

  static int monthly(List<PeriodicPayment> list) => list.fold(0, (s, p) => s + p.monthlyCents);
}
