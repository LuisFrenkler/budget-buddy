// Ahead as an agent, not a chat: it looks through taxes, contracts and
// deadlines on its own, lays each find before the person with one question,
// does it after a yes and later checks that the money really arrived.
// The feed on the start screen shows what it found; the chat is only the input.
import 'package:hive/hive.dart';
import '../l10n/l10n.dart';
import '../models/transaction.dart';
import '../utils/dates.dart';
import '../utils/merchant.dart';
import '../utils/money.dart';
import 'cancellation_service.dart';
import 'hints_service.dart';
import 'net_salary.dart';
import 'tax_estimate.dart';

enum FindKind { tax, waiting, money, done }

class AgentFind {
  final String id;
  final FindKind kind;
  final String title, text, action;
  // the least the person gets back, when Ahead can say it; per year when [yearly]
  final int? cents;
  final bool yearly;
  // tax: the most it can bring, when the least is not sure yet
  final int? upTo;
  // tax: the year whose page opens; a tax find without year opens the check
  final int? year;
  // otherwise: what Ahead is asked to do after the yes
  final String? question;
  const AgentFind(this.id, this.kind, this.title, this.text, this.action,
      {this.cents, this.yearly = false, this.upTo, this.year, this.question});
}

class AheadAgent {
  // hint kinds that are about money the person loses: the agent's work
  static const moneyKinds = {
    HintKind.stillCharging,
    HintKind.priceUp,
    HintKind.doubleCharge,
    HintKind.subTip,
    HintKind.bankFees,
    HintKind.dunning,
    HintKind.returnedDebit,
  };

  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  // "Später": the find comes back after a week
  static Map<String, DateTime> get snoozed => {
        for (final e in ((_box?.get('agentSnoozed') as Map?) ?? const {}).entries)
          if (DateTime.tryParse('${e.value}') != null) '${e.key}': DateTime.parse('${e.value}')
      };

  static Future<void> snooze(String id, {DateTime? now, int days = 7}) async {
    final until = (now ?? DateTime.now()).add(Duration(days: days));
    await _box?.put('agentSnoozed', {
      for (final e in snoozed.entries) e.key: e.value.toIso8601String(),
      id: until.toIso8601String(),
    });
  }

  static bool _hasProfile(int year) => _box?.get('taxProfile:$year') != null || _box?.get('taxProfile') != null;

  // what the agent has found right now, most money first; done items last
  static List<AgentFind> run({required List<Transaction> tx, List<Hint> hints = const [], DateTime? now}) {
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final later = snoozed;
    final tax = <AgentFind>[], waiting = <AgentFind>[], money = <AgentFind>[], done = <AgentFind>[];
    final open = TaxEstimate.openYears(today);

    for (final y in open) {
      final a = TaxEstimate.assessment(y);
      if (a != null) {
        // the notice arrived lately: show what came back, once it is real
        if (a.refund > 0 && day.difference(a.date).inDays <= 60) {
          done.add(AgentFind('tax-done-$y', FindKind.done, tr('Steuer {y}: {x} zurück', {'y': y, 'x': Money.format((a.refund * 100).round())}),
              tr('Laut Bescheid vom {d}.', {'d': Dates.full(a.date)}), tr('Ansehen'),
              cents: (a.refund * 100).round(), year: y));
        }
        continue;
      }
      if (TaxEstimate.filedAt(y) != null) {
        waiting.add(AgentFind('tax-wait-$y', FindKind.waiting, tr('Steuer {y}: abgegeben', {'y': y}),
            tr('Ich warte mit dir auf den Bescheid. Kommt er, mach ein Foto, dann prüfe ich ihn.'), tr('Bescheid fotografieren'),
            year: y));
        continue;
      }
      if (!_hasProfile(y)) continue;
      final p = TaxEstimate.profile(year: y);
      if (p.grossMonth <= 0 && p.grossYear == null) continue;
      final receipts = TaxEstimate.counted(tx, y).fold<int>(0, (s, c) => s + c.tx.amountCents) / 100;
      final r = TaxEstimate.range(p, receipts: receipts, year: y);
      if (r.high < 50) continue;
      final left = TaxEstimate.deadline(y).difference(day).inDays;
      if (later['tax-$y']?.isAfter(today) == true && left > 30) continue;
      tax.add(_taxFind(y, r.low, r.high, day));
    }

    // nothing about taxes yet: the first job is to look
    if (open.isNotEmpty && tax.isEmpty && waiting.isEmpty && !open.any(_hasProfile) && later['tax-check']?.isAfter(today) != true) {
      tax.add(AgentFind('tax-check', FindKind.tax, tr('Deine Steuer habe ich noch nicht geprüft'),
          tr('Bis zu vier Jahre lassen sich zurückholen. Drei Antworten, dann sage ich dir, was drin ist.'), tr('Prüfen')));
    }

    for (final h in hints) {
      if (!moneyKinds.contains(h.kind) || later[h.id]?.isAfter(today) == true) continue;
      money.add(AgentFind(h.id, FindKind.money, h.title, h.text, tr('Erledigen'),
          cents: h.cents, yearly: h.yearly, question: h.question ?? tr('Kümmer dich darum: {x}', {'x': h.title})));
    }

    tax.sort((a, b) => (b.cents ?? 0).compareTo(a.cents ?? 0));
    money.sort((a, b) => (b.cents ?? 0).compareTo(a.cents ?? 0));
    return [...tax, ...money, ...waiting, ...done];
  }

  static AgentFind _taxFind(int y, double lowEuro, double highEuro, DateTime day) {
    final left = TaxEstimate.deadline(y).difference(day).inDays;
    final low = (lowEuro.clamp(0, double.infinity) * 100).round();
    return AgentFind(
      'tax-$y',
      FindKind.tax,
      low > 0
          ? tr('Steuer {y}: mindestens {x} zurück', {'y': y, 'x': Money.format(low)})
          : tr('Steuer {y}: bis zu {x} zurück', {'y': y, 'x': Money.format((highEuro * 100).round())}),
      left <= 60
          ? tr('Noch {n} Tage, danach ist das Geld weg. Ich führe dich Schritt für Schritt durch.', {'n': left})
          : tr('Abgabe bis {d}. Ich führe dich Schritt für Schritt durch.', {'d': Dates.full(TaxEstimate.deadline(y))}),
      tr('Ja, los'),
      cents: low,
      upTo: (highEuro * 100).round(),
      year: y,
    );
  }

  // before sign-up: the finds from the refund check, so the guest sees the agent's work too
  static List<AgentFind> guestFinds({DateTime? now}) {
    final today = now ?? DateTime.now();
    final c = _box?.get('refundCheck');
    if (c is! Map) return const [];
    final years = TaxEstimate.quickCheck(
      startYear: (c['startYear'] as num).toInt(),
      startMonth: (c['startMonth'] as num).toInt(),
      grossMonth: (c['grossMonth'] as num).toDouble(),
      km: (c['km'] as num?)?.toDouble() ?? 0,
      today: today,
    );
    final day = DateTime(today.year, today.month, today.day);
    return [
      for (final q in years)
        if (q.deadline != null && q.high >= 50) _taxFind(q.year, q.low, q.high, day)
    ]..sort((a, b) => (b.cents ?? 0).compareTo(a.cents ?? 0));
  }

  // money that really arrived or stopped going out: tax refunds from the notice
  // and contracts whose payments stopped after Ahead's cancellation letter
  static int recoveredCents({required List<Transaction> tx, DateTime? now}) {
    final today = now ?? DateTime.now();
    var cents = 0;
    for (var y = NetSalary.firstYear; y <= today.year; y++) {
      // only years filed through Ahead: money it did not help with is not its find
      // shortcut: "abgegeben" is the person's own tap; use the ERiC receipt once filing runs through Ahead
      final a = TaxEstimate.assessment(y);
      if (a != null && a.refund > 0 && TaxEstimate.filedAt(y) != null) cents += (a.refund * 100).round();
    }
    // the ledger only proves a debit stopped up to its newest booking (a new
    // bank or no import would look like savings otherwise)
    final seen = tx.isEmpty ? null : tx.map((t) => t.date).reduce((a, b) => a.isAfter(b) ? a : b);
    for (final e in CancellationService.all.entries) {
      final key = Merchant.key(e.key);
      final sent = e.value;
      // too early to tell whether the payments stopped
      if (seen == null || today.isBefore(sent.add(const Duration(days: 35)))) continue;
      final paid = tx.where((t) => !t.isIncome && Merchant.key(t.note ?? '') == key).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      // the debits must have stopped; one last debit in the notice period is fine
      final until = seen.isBefore(today) ? seen : today;
      if (paid.length < 2 || until.difference(paid.last.date).inDays <= 35) continue;
      if (paid.last.date.isBefore(sent.subtract(const Duration(days: 35)))) continue;
      // monthly debits only: a yearly plan is not twelve savings
      final gap = paid.last.date.difference(paid[paid.length - 2].date).inDays;
      if (gap < 25 || gap > 35) continue;
      // every monthly debit that did not come since the last one, up to the newest booking
      final last = paid.last;
      var months = 0;
      while (!DateTime(last.date.year, last.date.month + months + 1, last.date.day).isAfter(until)) {
        months++;
      }
      cents += months * last.amountCents;
    }
    return cents;
  }

  // the most the open finds can bring: for the headline while the least is still zero
  static int upToCents(List<AgentFind> finds) => finds
      .where((f) => f.kind == FindKind.tax || f.kind == FindKind.money)
      .fold(0, (s, f) => s + (f.upTo ?? f.cents ?? 0));

  // the least still waiting in open finds: tax back, money to reclaim, a year of a cost that can stop
  static int openCents(List<AgentFind> finds) => finds
      .where((f) => f.kind == FindKind.tax || f.kind == FindKind.money)
      .fold(0, (s, f) => s + (f.cents ?? 0));
}
