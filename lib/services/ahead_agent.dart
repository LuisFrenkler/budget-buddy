// Ahead as an agent, not a chat: it looks through taxes, contracts and
// deadlines on its own, lays each find before the person with one question,
// does it after a yes and later checks that the money really arrived.
// The feed on the start screen shows what it found; the chat is only the input.
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../l10n/l10n.dart';
import '../models/transaction.dart';
import '../utils/dates.dart';
import '../utils/merchant.dart';
import '../utils/money.dart';
import 'cancellation_service.dart';
import 'contracts.dart';
import 'hints_service.dart';
import 'net_salary.dart';
import 'oddities.dart';
import 'tax_estimate.dart';

enum FindKind { tax, waiting, money, done }

// where the money back stands against the guarantee
enum GuaranteeTier { nothing, under, reached }

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
  // money: the contract whose cancellation letter is ready, when the find is about one
  final String? contract;
  const AgentFind(this.id, this.kind, this.title, this.text, this.action,
      {this.cents, this.yearly = false, this.upTo, this.year, this.question, this.contract});
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

  // money that is lost within days unless the person acts: these lead the start, in this order
  static const urgentKinds = [HintKind.overdraft, HintKind.returnedDebit, HintKind.dunning];

  // a hint the agent lays out as a find (so nothing else repeats it)
  static bool takes(HintKind k) => moneyKinds.contains(k) || urgentKinds.contains(k);

  // the offer: the membership fee, and what Ahead has to get back within
  // twelve months of joining, or the whole fee is refunded
  static const monthlyFeeCents = 499;
  static const yearlyFeeCents = 4900;
  static const guaranteeCents = 2 * yearlyFeeCents;

  static GuaranteeTier guaranteeTier(int cents) => cents >= guaranteeCents
      ? GuaranteeTier.reached
      : cents > 0
          ? GuaranteeTier.under
          : GuaranteeTier.nothing;

  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  // bumped when what the agent can find changed outside the feed (the refund check was adopted)
  static final changed = ValueNotifier<int>(0);

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

  // what the agent has found right now: what burns within days, then what is lost
  // every month, then the money to get back; done items last
  static List<AgentFind> run({required List<Transaction> tx, List<Hint> hints = const [], DateTime? now}) {
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final later = snoozed;
    final tax = <AgentFind>[], waiting = <AgentFind>[], money = <AgentFind>[], done = <AgentFind>[];
    final urgent = <AgentFind>[], look = <AgentFind>[];
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

    // right after sign-up the refund check is not adopted yet: show its finds already
    if (!open.any(_hasProfile)) tax.addAll(guestFinds(now: today).where((f) => later[f.id]?.isAfter(today) != true));

    // nothing about taxes yet: the first job is to look
    // (a check with nothing in it is still a check: no "noch nicht geprüft" then)
    if (open.isNotEmpty &&
        tax.isEmpty &&
        waiting.isEmpty &&
        !open.any(_hasProfile) &&
        _box?.get('refundCheck') == null &&
        later['tax-check']?.isAfter(today) != true) {
      tax.add(AgentFind('tax-check', FindKind.tax, tr('Deine Steuer habe ich noch nicht geprüft'),
          tr('Bis zu vier Jahre lassen sich zurückholen. Drei Antworten, dann sage ich dir, was drin ist.'), tr('Prüfen')));
    }

    // the running year cannot be filed yet: Ahead keeps it in view so the start is never empty
    final thisYear = today.year;
    if (_hasProfile(thisYear) && TaxEstimate.filedAt(thisYear) == null) {
      final p = TaxEstimate.profile(year: thisYear);
      if (p.grossMonth > 0 || p.grossYear != null) {
        final receipts = TaxEstimate.counted(tx, thisYear).fold<int>(0, (s, c) => s + c.tx.amountCents) / 100;
        final r = TaxEstimate.range(p, receipts: receipts, year: thisYear);
        if (r.high >= 50) {
          waiting.add(AgentFind('tax-$thisYear', FindKind.waiting,
              tr('Steuer {y}: bis zu {x} zurück', {'y': thisYear, 'x': Money.format((r.high * 100).round())}),
              tr('Ab dem 1. Januar kannst du abgeben. Bis dahin sammle ich deine Belege.'), tr('Ansehen'),
              year: thisYear));
        }
      }
    }

    // rent is no contract an agent cancels or gets cheaper
    final contracts = Contracts.cancellable(Contracts.detect(tx, now: today));
    // what burns in a fixed order; the rest as the hints come, heaviest first
    // (still charging, price rise, double charge, fees)
    final ordered = [
      for (final k in urgentKinds) ...hints.where((h) => h.kind == k),
      ...hints.where((h) => !urgentKinds.contains(h.kind)),
    ];
    for (final h in ordered) {
      if (!takes(h.kind) || later[h.id]?.isAfter(today) == true) continue;
      // a price rise or a cheaper plan is about one contract: its letter is ready
      // shortcut: matched by the hint id; give Hint a contract field once hints_service can change
      final contract = contracts
          .where((c) =>
              h.id == 'price-${c.name}-${c.last.date.toIso8601String().substring(0, 10)}' ||
              h.id == 'abo-tip-${today.year}-${Merchant.key(c.name)}')
          .firstOrNull
          ?.name;
      // the letter went out: the find is done
      if (contract != null && CancellationService.sentAt(contract) != null) continue;
      (urgentKinds.contains(h.kind) ? urgent : money).add(AgentFind(
          h.id, FindKind.money, h.title, h.text, h.kind == HintKind.overdraft ? tr('Plan machen') : tr('Erledigen'),
          cents: h.cents,
          yearly: h.yearly,
          question: h.question ?? tr('Kümmer dich darum: {x}', {'x': h.title}),
          contract: contract));
    }

    // no single trap found: the running contracts are still worth one look together
    if (money.isEmpty && contracts.isNotEmpty && later['contracts']?.isAfter(today) != true) {
      look.add(AgentFind(
          'contracts',
          FindKind.money,
          contracts.length == 1
              ? tr('{name} kostet dich {x} im Jahr', {'name': contracts.single.name, 'x': Money.format(contracts.single.monthlyCents * 12)})
              : tr('{n} Verträge kosten dich {x} im Jahr', {'n': contracts.length, 'x': Money.format(Contracts.monthlyTotal(contracts) * 12)}),
          contracts.length == 1
              ? tr('Ich prüfe mit dir, ob du kündigen oder es günstiger bekommen kannst.')
              : tr('Ich gehe sie mit dir durch und sage dir, welche du kündigen oder günstiger bekommen kannst.'),
          tr('Durchgehen'),
          // the question carries the card's numbers, so the answer starts from the same sum
          question: contracts.length == 1
              ? tr('Prüf mit mir den Vertrag {name} für {x} im Jahr: Kann ich kündigen oder es günstiger bekommen?',
                  {'name': contracts.single.name, 'x': Money.format(contracts.single.monthlyCents * 12)})
              : tr('Geh meine {n} Verträge für zusammen {x} im Jahr mit mir durch: Welche kann ich kündigen oder günstiger bekommen?',
                  {'n': contracts.length, 'x': Money.format(Contracts.monthlyTotal(contracts) * 12)})));
    }

    tax.sort((a, b) => (b.cents ?? 0).compareTo(a.cents ?? 0));
    // a year that ends within 30 days is money lost within days too
    bool ends(AgentFind f) => f.year != null && TaxEstimate.deadline(f.year!).difference(day).inDays <= 30;
    final lead = [...urgent, ...tax.where(ends), ...money];
    tax.removeWhere(ends);
    // a refund is the biggest money: the best year stays among the three on the start, behind what burns
    if (tax.isNotEmpty && lead.length > 2 && urgent.length < 3 && !lead.any((f) => f.kind == FindKind.tax)) {
      lead.insert(2, tax.removeAt(0));
    }
    return [...lead, ...tax, ...look, ...waiting, ...done];
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
          ? tr('Noch {n} Tage, danach ist das Geld weg.', {'n': left})
          : tr('Abgabe bis {d}.', {'d': Dates.full(TaxEstimate.deadline(y))}),
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

  // money that really arrived or stopped going out: tax refunds from the notice,
  // contracts whose payments stopped after Ahead's cancellation letter, and
  // double charges that were paid back. With [since] (the day of joining) only
  // what arrived on or after that day: the measure of the guarantee.
  static int recoveredCents({required List<Transaction> tx, DateTime? now, DateTime? since}) {
    final today = now ?? DateTime.now();
    final from = since == null ? null : DateTime(since.year, since.month, since.day);
    bool counts(DateTime d) => from == null || !d.isBefore(from);
    var cents = 0;
    for (var y = NetSalary.firstYear; y <= today.year; y++) {
      // only years filed through Ahead: money it did not help with is not its find
      // shortcut: "abgegeben" is the person's own tap; use the ERiC receipt once filing runs through Ahead
      final a = TaxEstimate.assessment(y);
      if (a != null && a.refund > 0 && TaxEstimate.filedAt(y) != null && counts(a.date)) cents += (a.refund * 100).round();
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
      for (var k = 1;; k++) {
        final due = DateTime(last.date.year, last.date.month + k, last.date.day);
        if (due.isAfter(until)) break;
        if (counts(due)) months++;
      }
      cents += months * last.amountCents;
    }
    // a double charge paid back: the same amount from the same merchant arrives
    // within eight weeks of the second debit
    // shortcut: a merchant's own reversal counts too; count only reclaims sent through Ahead once it sends them
    final back = <String>{};
    for (final d in Oddities.doubles(tx, now: today, days: 3650)) {
      final key = Merchant.key(d.second.note ?? '');
      if (key.isEmpty) continue;
      for (final t in tx) {
        if (!t.isIncome || t.amountCents != d.cents || back.contains(t.id) || Merchant.key(t.note ?? '') != key) continue;
        if (t.date.isBefore(d.second.date) || t.date.isAfter(today) || t.date.difference(d.second.date).inDays > 56) continue;
        if (!counts(t.date)) continue;
        back.add(t.id);
        cents += d.cents;
        break;
      }
    }
    return cents;
  }

  static Iterable<AgentFind> _asks(List<AgentFind> finds) =>
      finds.where((f) => f.kind == FindKind.tax || f.kind == FindKind.money);

  // the most the open finds can bring back: for the headline while the least is still zero
  static int upToCents(List<AgentFind> finds) =>
      _asks(finds).where((f) => !f.yearly).fold(0, (s, f) => s + (f.upTo ?? f.cents ?? 0));

  // the least that comes back from open finds: tax, money to reclaim
  static int openCents(List<AgentFind> finds) =>
      _asks(finds).where((f) => !f.yearly).fold(0, (s, f) => s + (f.cents ?? 0));

  // costs per year that can stop (a price rise, bank fees): saved, not paid back
  static int yearlyCents(List<AgentFind> finds) =>
      _asks(finds).where((f) => f.yearly).fold(0, (s, f) => s + (f.cents ?? 0));
}
