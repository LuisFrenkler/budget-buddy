// Smart hints: things worth knowing right now, worked out from the user's own
// data. A budget about to tip, a contract that got more expensive, a big
// payment coming up, the free trial ending, the bank link running out.
//
// Each hint has an id that includes its period (month, date), so a dismissed
// hint stays away until the situation comes up again.
import 'package:hive/hive.dart';
import '../models/budget.dart';
import '../models/goal.dart';
import '../models/transaction.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import 'cancellation_service.dart';
import 'contracts.dart';
import 'plus_service.dart';
import 'split_service.dart';
import '../l10n/l10n.dart';
import 'buddy_log.dart';
import 'income_sources.dart';
import 'installments.dart';
import 'oddities.dart';
import 'periodic_payments.dart';
import 'overdraft.dart';
import 'tax_estimate.dart';

enum HintKind {
  budgetOver,
  budgetClose,
  priceUp,
  upcoming,
  trialEnds,
  bankExpires,
  bigExpense,
  doubleCharge,
  weekPlan,
  bankFees,
  goalDue,
  stillCharging,
  splitNew,
  salaryIn,
  salaryUp,
  budgetUnreal,
  taxReturn,
  monthReview,
  lowMonth,
  goalReached,
  goalBehind,
  overdraft,
  returnedDebit,
  dunning,
  incomeMissing,
  installments,
  followUp,
  periodicDue,
}

// where tapping a hint leads
enum HintTarget { budgets, contracts, subscription, connections, transactions, goals, splits, buddy }

class Hint {
  final String id;
  final HintKind kind;
  final String title;
  final String text;
  final HintTarget target;
  final bool urgent;
  // what to ask Buddy when the hint is tapped (a notification opens his chat)
  final String? question;

  const Hint(this.id, this.kind, this.title, this.text, this.target, {this.urgent = false, this.question});

  // how much this hint matters right now: what is at stake and how soon it
  // has to be done. The app shows the highest first, Buddy opens with it.
  int get weight => (urgent ? 100 : 0) + (HintsService.weights[kind] ?? 10);
}

class HintsService {
  // money that is going out by mistake comes first, then what runs out soon,
  // then moments and plans, then plain information
  static const weights = {
    HintKind.stillCharging: 90,
    HintKind.dunning: 89,
    HintKind.incomeMissing: 75,
    HintKind.installments: 47,
    HintKind.followUp: 33,
    HintKind.periodicDue: 52,
    HintKind.overdraft: 88,
    HintKind.returnedDebit: 86,
    HintKind.doubleCharge: 85,
    HintKind.lowMonth: 80,
    HintKind.budgetOver: 70,
    HintKind.trialEnds: 70,
    HintKind.bankExpires: 65,
    HintKind.salaryIn: 60,
    HintKind.salaryUp: 62,
    HintKind.monthReview: 55,
    HintKind.priceUp: 55,
    HintKind.bigExpense: 50,
    HintKind.goalReached: 50,
    HintKind.goalDue: 45,
    HintKind.bankFees: 45,
    HintKind.goalBehind: 40,
    HintKind.budgetClose: 40,
    HintKind.budgetUnreal: 42,
    HintKind.taxReturn: 44,
    HintKind.splitNew: 35,
    HintKind.weekPlan: 30,
    HintKind.upcoming: 20,
  };

  // the one hint that counts today, if any: for Buddy's opening and the home tip
  static Hint? top(List<Hint> hints, {bool askable = false}) {
    final list = askable ? hints.where((h) => h.question != null || h.target == HintTarget.buddy).toList() : hints;
    return list.isEmpty ? null : list.first;
  }

  static Box get _box => Hive.box('settings');

  static Set<String> get dismissed => ((_box.get('hintsDismissed') as List?) ?? const []).cast<String>().toSet();

  // brings a hint back right after it was swiped away by mistake
  static Future<void> undismiss(String id) async {
    await _box.put('hintsDismissed', [...dismissed]..remove(id));
  }

  static Future<void> dismiss(String id) async {
    // keep the list short: old periods never come back anyway
    final list = [...dismissed, id];
    await _box.put('hintsDismissed', list.length > 200 ? list.sublist(list.length - 200) : list);
  }

  static List<Hint> current({
    required List<Transaction> tx,
    required List<Budget> budgets,
    required List<Goal> goals,
    Subscription? subscription,
    DateTime? bankValidUntil,
    int? freeCents,
    int? balanceCents,
    DateTime? now,
  }) {
    final hidden = dismissed;
    final cancellations = CancellationService.all;
    return build(
      tx: tx,
      budgets: budgets,
      goals: goals,
      subscription: subscription,
      bankValidUntil: bankValidUntil,
      cancellations: cancellations,
      splitNews: Hive.isBoxOpen('splits') ? SplitService.news() : const [],
      freeCents: freeCents,
      balanceCents: balanceCents,
      done: BuddyLog.all(),
      now: now,
    ).where((h) => !hidden.contains(h.id)).toList();
  }

  // spending of a category in each of the last three full months; a new
  // limit when every one was more than 5 % over: the middle month, a bit
  // trimmed and rounded up to 10 €, but never more than the highest month
  static ({int averageCents, int suggestCents})? realisticBudget(List<Transaction> tx, String category, int limit,
      {DateTime? now}) {
    final today = now ?? DateTime.now();
    final months = [
      for (var i = 1; i <= 3; i++) DateTime(today.year, today.month - i),
    ];
    final spent = [
      for (final m in months)
        tx
            .where((t) => t.category == category && t.date.year == m.year && t.date.month == m.month)
            .fold<int>(0, (s, t) => s + (t.isIncome ? -t.amountCents : t.amountCents))
    ];
    if (spent.any((s) => s <= limit * 1.05)) return null;
    final sorted = [...spent]..sort();
    final avg = spent.fold<int>(0, (a, b) => a + b) ~/ 3;
    var suggest = ((sorted[1] * 0.95) / 1000).ceil() * 1000;
    if (suggest > sorted.last) suggest = sorted.last;
    if (suggest <= limit) return null;
    return (averageCents: avg, suggestCents: suggest);
  }

  // the salary of the last 40 days against the usual one of the three months
  // before: a raise when it is at least 3 % and 50 € higher
  static ({int raiseCents, int nowCents, int beforeCents})? salaryRaise(List<Transaction> tx, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final salaries = tx.where((t) => t.isEarning && t.category == 'Gehalt' && t.amountCents >= 50000).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (salaries.length < 4) return null;
    final latest = salaries.first;
    if (_daysBetween(latest.date, today) > 40 || _daysBetween(latest.date, today) < 0) return null;
    // one salary per month: the largest of each month before the latest one
    final byMonth = <String, int>{};
    for (final t in salaries.skip(1)) {
      if (t.date.year == latest.date.year && t.date.month == latest.date.month) continue;
      final k = '${t.date.year}-${t.date.month}';
      if ((byMonth[k] ?? 0) < t.amountCents) byMonth[k] = t.amountCents;
    }
    final before = byMonth.values.take(3).toList()..sort();
    if (before.length < 3) return null;
    final usual = before[1];
    final diff = latest.amountCents - usual;
    if (diff < 5000 || diff < usual * 0.03) return null;
    // a one-off (bonus, holiday pay) is not a raise: it has to be far below double
    if (latest.amountCents > usual * 1.5) return null;
    return (raiseCents: diff, nowCents: latest.amountCents, beforeCents: usual);
  }

  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime(b.year, b.month, b.day).difference(DateTime(a.year, a.month, a.day)).inDays;

  static String _inDays(int d) => d <= 0 ? tr('heute') : d == 1 ? tr('morgen') : tr('in {d} Tagen', {'d': d});

  // all hints for the data, most urgent first
  static List<Hint> build({
    required List<Transaction> tx,
    required List<Budget> budgets,
    required List<Goal> goals,
    Subscription? subscription,
    DateTime? bankValidUntil,
    Map<String, DateTime> cancellations = const {},
    List<({String group, String groupId, String title, int cents, String by})> splitNews = const [],
    // what is left for the month after fixed costs (the forecast), if known
    int? freeCents,
    // the cash on the accounts today, if known (for the overdraft warning)
    int? balanceCents,
    // what Buddy's cards changed lately, to ask a week later how it went
    List<BuddyLogEntry> done = const [],
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final month = '${today.year}-${today.month}';
    final out = <Hint>[];

    // a week after a card was taken: how is it going?
    final followUp = done
        .where((e) =>
            !e.undone &&
            const {'budget', 'goal', 'cancel', 'save'}.contains(e.kind) &&
            _daysBetween(e.at, today) >= 7 &&
            _daysBetween(e.at, today) <= 10)
        .toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    if (followUp.isNotEmpty) {
      final e = followUp.first;
      out.add(Hint(
          'followup-${e.id}',
          HintKind.followUp,
          tr('Eine Woche später: {x}', {'x': e.title}),
          switch (e.kind) {
            'cancel' => tr('Ist die Kündigung bestätigt? Ohne Bestätigung lieber nachhaken.'),
            'budget' => tr('Buddy schaut mit dir, ob das Budget passt oder angepasst werden sollte.'),
            _ => tr('Buddy schaut mit dir, ob du im Plan bist.'),
          },
          HintTarget.buddy,
          question: switch (e.kind) {
            'cancel' => tr('Vor einer Woche habe ich gekündigt: {x}. Was mache ich, wenn keine Bestätigung kommt?', {'x': e.title}),
            'budget' => tr('Wie läuft mein Budget seit einer Woche: {x}?', {'x': e.title}),
            _ => tr('Wie komme ich voran seit letzter Woche: {x}?', {'x': e.title}),
          }));
    }

    // a yearly or quarterly payment of 100 € or more within the next month
    for (final pp in PeriodicPayments.detect(tx, now: today)) {
      final days = _daysBetween(today, pp.next);
      if (days < 0 || days > 30 || pp.cents < 10000) continue;
      out.add(Hint(
          'periodic-${pp.name}-${pp.next.year}-${pp.next.month}',
          HintKind.periodicDue,
          tr('{x}: {y} {z}', {'x': pp.name, 'y': Money.format(pp.cents), 'z': _inDays(days)}),
          tr('Kommt nicht jeden Monat, deshalb leicht vergessen. Ab jetzt {x} im Monat zurücklegen, dann tut es nächstes Mal nicht weh.',
              {'x': Money.format(pp.monthlyCents)}),
          HintTarget.buddy,
          question: tr('{x} kommt bald mit {y}. Wie lege ich für solche Jahreszahlungen am besten zurück?',
              {'x': pp.name, 'y': Money.format(pp.cents)})));
      break;
    }

    // buy now, pay later adds up: once a month when there are some
    final rates = Installments.detect(tx, now: today);
    if (rates.isNotEmpty) {
      final sum = Installments.monthly(rates);
      out.add(Hint(
          'installments-$month',
          HintKind.installments,
          tr('{n} Ratenzahlungen: {x} im Monat', {'n': rates.length, 'x': Money.format(sum)}),
          tr('Jede einzeln ist klein, zusammen sind es {x} im Jahr. Buddy zeigt dir, welche zuerst weg sollte.',
              {'x': Money.format(sum * 12)}),
          HintTarget.buddy,
          question: tr('Ich zahle {x} im Monat für Ratenkäufe. Wie werde ich die am schnellsten los?', {'x': Money.format(sum)})));
    }

    // the account runs below zero before the next salary
    if (balanceCents != null) {
      final risk = Overdraft.check(tx, balanceCents: balanceCents, now: today);
      if (risk != null) {
        out.add(Hint(
            'overdraft-${risk.payday.year}-${risk.payday.month}-${risk.payday.day}',
            HintKind.overdraft,
            tr('Konto rutscht vor dem Gehalt ins Minus'),
            tr('Bis zum Gehalt am {d} fehlen voraussichtlich {x}.{due} Jetzt umplanen ist billiger als Dispozinsen.', {
              'd': Dates.dayMonth(risk.payday),
              'x': Money.format(risk.shortCents),
              'due': risk.dueNames.isEmpty ? '' : tr(' Vorher wird noch {x} abgebucht.', {'x': risk.dueNames.join(', ')}),
            }),
            HintTarget.buddy,
            urgent: true,
            question: tr('Mein Konto rutscht vor dem Gehalt ins Minus. Wie komme ich ohne Dispo bis zum {d}?',
                {'d': Dates.dayMonth(risk.payday)})));
      }
    }

    // a reminder fee or a debt collector: something is unpaid, act before it grows
    final dun = Oddities.dunning(tx, now: today);
    if (dun.isNotEmpty) {
      final d = dun.first;
      final who = d.tx.note ?? tr(d.tx.category);
      out.add(Hint(
          'dunning-${d.tx.id}',
          HintKind.dunning,
          d.collector ? tr('Zahlung an ein Inkassobüro') : tr('Mahngebühr bei {x}', {'x': who}),
          d.collector
              ? tr('{x} an {y}. Prüf zuerst, ob die Forderung stimmt, bevor du weiter zahlst. Die Verbraucherzentrale hilft dabei.',
                  {'x': Money.format(d.tx.amountCents), 'y': who})
              : tr('{x} für eine verspätete Zahlung. Prüf, welche Rechnung offen ist, und zahl sie, bevor Inkasso daraus wird.',
                  {'x': Money.format(d.tx.amountCents)}),
          HintTarget.buddy,
          urgent: d.collector,
          question: d.collector
              ? tr('Ich habe Geld an ein Inkassobüro ({x}) gezahlt. Was muss ich jetzt prüfen?', {'x': who})
              : tr('Ich habe eine Mahngebühr von {x} bezahlt. Wie verhindere ich das in Zukunft?', {'x': who})));
    }

    // money that comes every month is late this time
    for (final m in IncomeSources.missing(tx, now: today).take(2)) {
      final who = m.kind == 'gehalt' ? tr('Dein Gehalt') : m.name;
      out.add(Hint(
          'income-missing-${m.key}-$month',
          HintKind.incomeMissing,
          tr('{x} ist noch nicht da', {'x': who}),
          tr('Sonst kommt es um den {d}., meist {x}. Frag kurz beim Absender nach, bevor es knapp wird.',
              {'d': m.day, 'x': Money.format(m.monthlyCents)}),
          HintTarget.buddy,
          urgent: m.kind == 'gehalt',
          question: tr('{x} ist diesen Monat noch nicht gekommen. Was mache ich, und reicht mein Geld bis dahin?', {'x': who})));
    }

    // a direct debit came back: the bill is still open
    for (final r in Oddities.returnedDebits(tx, now: today)) {
      out.add(Hint(
          'returned-${r.back.id}',
          HintKind.returnedDebit,
          tr('Lastschrift von {x} ging zurück', {'x': r.merchant}),
          tr('{x} sind wieder auf deinem Konto, die Rechnung ist aber noch offen. Meist folgt eine Mahnung mit Gebühr.',
              {'x': Money.format(r.cents)}),
          HintTarget.buddy,
          question: tr('Eine Lastschrift von {x} über {y} ist zurückgegangen. Was muss ich jetzt tun?',
              {'x': r.merchant, 'y': Money.format(r.cents)})));
    }

    // budgets of the running period
    for (final b in budgets) {
      if (today.isBefore(b.startDate) || today.isAfter(b.endDate.add(const Duration(days: 1)))) continue;
      if (b.limitCents <= 0) continue;
      final share = b.spentCents / b.limitCents;
      final daysLeft = _daysBetween(today, b.endDate);
      if (share >= 1) {
        out.add(Hint('budget-over-${b.category}-$month', HintKind.budgetOver, tr('{x}: Budget überschritten', {'x': b.category}),
            tr('{x} drüber. Vielleicht das Limit anpassen?', {'x': Money.format(b.spentCents - b.limitCents)}), HintTarget.budgets,
            urgent: true));
      } else if (share >= 0.8 && daysLeft >= 3) {
        out.add(Hint(
            'budget-close-${b.category}-$month',
            HintKind.budgetClose,
            tr('{x}: {y} % weg', {'x': tr(b.category), 'y': (share * 100).round()}),
            tr('Noch {x} für {daysLeft} Tage, also etwa {y} am Tag.', {'x': Money.format(b.limitCents - b.spentCents), 'daysLeft': daysLeft, 'y': Money.format((b.limitCents - b.spentCents) ~/ daysLeft)}),
            HintTarget.budgets,
            question: tr('Wie komme ich mit {x} bis Monatsende hin?', {'x': b.category})));
      }
    }

    // the first three days of a month: close the last one with Buddy
    if (today.day <= 3) {
      final last = DateTime(today.year, today.month - 1);
      final had = tx.where((t) => t.date.year == last.year && t.date.month == last.month).length;
      if (had >= 10) {
        const names = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober',
          'November', 'Dezember'];
        final m = tr(names[last.month - 1]), n = tr(names[today.month - 1]);
        out.add(Hint('month-${last.year}-${last.month}', HintKind.monthReview, tr('Dein Monatsabschluss'),
            tr('{m} ist vorbei. Zwei Minuten mit Buddy: was lief gut und was ist der Plan für {n}?', {'m': m, 'n': n}),
            HintTarget.buddy,
            question: tr('Lass uns {m} abschließen: Was lief gut, was nicht, und was ist der Plan für {n}?',
                {'m': m, 'n': n})));
      }
    }

    // February to July: the tax return for last year, when money comes back
    if (today.month >= 2 && today.month <= 7) {
      final last = today.year - 1;
      final salaries = tx.where((t) => t.isEarning && t.category == 'Gehalt' && t.date.year == last).toList();
      final profile = TaxEstimate.profile();
      String? body;
      if (profile.grossMonth > 0) {
        final receipts = TaxEstimate.counted(tx, last).fold<int>(0, (s, c) => s + c.tx.amountCents) / 100;
        final back = TaxEstimate.compute(profile, receipts: receipts).refund;
        if (back >= 50) {
          body = tr('Nach deinen Angaben kommen rund {x} zurück. Abgeben geht kostenlos über ELSTER.',
              {'x': Money.format((back * 100).round())});
        }
      } else if (salaries.isNotEmpty) {
        final months = salaries.map((t) => t.date.month).toSet().length;
        if (months < 12) {
          body = tr('Du hast {y} nur {n} Monate verdient. Dann kommt meist Lohnsteuer zurück.', {'y': last, 'n': months});
        }
      }
      if (body != null) {
        out.add(Hint('tax-$last-$month', HintKind.taxReturn, tr('Steuererklärung {y}', {'y': last}), body, HintTarget.buddy,
            question: tr('Lohnt sich meine Steuererklärung für {y}, und was brauche ich dafür?', {'y': last})));
      }
    }

    // a budget that has not held for three months: a realistic one instead
    for (final b in budgets) {
      final fit = realisticBudget(tx, b.category, b.limitCents, now: today);
      if (fit == null) continue;
      out.add(Hint(
          'budget-unreal-${b.category}-$month',
          HintKind.budgetUnreal,
          tr('Budget {x} passt nicht', {'x': tr(b.category)}),
          tr('Drei Monate über {x}, im Schnitt {y}. Ein Budget, das hält, motiviert mehr: etwa {z}.',
              {'x': Money.format(b.limitCents), 'y': Money.format(fit.averageCents), 'z': Money.format(fit.suggestCents)}),
          HintTarget.buddy,
          question: tr('Mein Budget für {x} ({y}) passt seit drei Monaten nicht. Welcher Betrag ist realistisch, und wo kann ich trotzdem sparen?',
              {'x': tr(b.category), 'y': Money.format(b.limitCents)})));
    }

    // a raise: the moment to save half of it before the spending grows with it
    final raise = salaryRaise(tx, now: today);
    if (raise != null) {
      final half = (raise.raiseCents / 2 / 100).round() * 100;
      out.add(Hint(
          'salary-up-${today.year}-${today.month}',
          HintKind.salaryUp,
          tr('Dein Gehalt ist gestiegen: +{x}', {'x': Money.format(raise.raiseCents)}),
          tr('Leg die Hälfte, {x} im Monat, gleich per Dauerauftrag zurück. Dann merkst du es nicht und hast trotzdem mehr.',
              {'x': Money.format(half)}),
          HintTarget.buddy,
          question: tr('Mein Gehalt ist um {x} im Monat gestiegen. Wie viel davon sollte ich sparen und wofür?',
              {'x': Money.format(raise.raiseCents)})));
    }

    // the salary arrived in the last two days: the moment to put some aside
    for (final t in tx) {
      if (!t.isEarning || t.category != 'Gehalt' || t.amountCents < 50000) continue;
      final d = _daysBetween(t.date, today);
      if (d < 0 || d > 2) continue;
      out.add(Hint('salary-${t.id}', HintKind.salaryIn, tr('Dein Gehalt ist da'),
          tr('{x} sind angekommen. Leg gleich einen Teil zur Seite, bevor der Monat ihn verteilt.', {'x': Money.format(t.amountCents)}),
          HintTarget.buddy,
          question: tr('Mein Gehalt ist da. Wie viel sollte ich davon zur Seite legen?')));
    }

    // the forecast says the month will not work out
    if (freeCents != null && freeCents < 0 && today.day <= 25) {
      out.add(Hint('low-$month-${today.day ~/ 7}', HintKind.lowMonth, tr('Der Monat wird knapp'),
          tr('Nach den festen Kosten fehlen bis Monatsende etwa {x}. Buddy hat einen Plan.', {'x': Money.format(-freeCents)}),
          HintTarget.buddy,
          urgent: true, question: tr('Mein Monat wird knapp. Was kann ich jetzt tun?')));
    }

    final contracts = Contracts.detect(tx, now: today);
    for (final c in contracts) {
      // cancelled, but the money still goes out
      final sent = cancellations[c.name.toLowerCase().trim()];
      if (sent != null && CancellationService.stillCharging(c, sent)) {
        out.add(Hint(
            'still-${c.name}-${c.last.date.toIso8601String().substring(0, 10)}',
            HintKind.stillCharging,
            tr('{x} bucht trotz Kündigung ab', {'x': c.name}),
            tr('Du hast am {x} gekündigt, am {y} kamen trotzdem {z}. Fordere das Geld zurück; eine Lastschrift kannst du 8 Wochen lang bei deiner Bank zurückgeben.', {'x': Dates.dayMonth(sent), 'y': Dates.dayMonth(c.last.date), 'z': Money.format(c.monthlyCents)}),
            HintTarget.contracts,
            urgent: true));
      }
      // a price rise in the last six weeks
      if (c.priceChange > 0 && _daysBetween(c.last.date, today) <= 42) {
        out.add(Hint(
            'price-${c.name}-${c.last.date.toIso8601String().substring(0, 10)}',
            HintKind.priceUp,
            tr('{x} ist teurer geworden', {'x': c.name}),
            tr('+{x} im Monat, jetzt {y}. Aufs Jahr sind das {z} mehr.', {'x': Money.format(c.priceChange), 'y': Money.format(c.monthlyCents), 'z': Money.format(c.priceChange * 12)}),
            HintTarget.contracts,
            urgent: true));
      }
      // a large fixed payment in the next three days
      final until = _daysBetween(today, c.nextDate);
      if (until >= 0 && until <= 3 && c.monthlyCents >= 5000) {
        out.add(Hint(
            'upcoming-${c.name}-${c.nextDate.toIso8601String().substring(0, 10)}',
            HintKind.upcoming,
            '${c.name} kommt ${_inDays(until)}',
            tr('{x} werden voraussichtlich am {y} abgebucht.', {'x': Money.format(c.monthlyCents), 'y': Dates.dayMonth(c.nextDate)}),
            HintTarget.contracts));
      }
    }

    // an expense of the last three days far above the usual in its category
    final recent = tx.where((t) => !t.isIncome && _daysBetween(t.date, today) <= 3 && _daysBetween(t.date, today) >= 0);
    for (final t in recent) {
      final same = tx
          .where((o) => !o.isIncome && o.category == t.category && o.id != t.id)
          .map((o) => o.amountCents)
          .toList()
        ..sort();
      if (same.length < 5 || t.amountCents < 10000) continue;
      final median = same[same.length ~/ 2];
      if (t.amountCents >= median * 3) {
        out.add(Hint(
            'big-${t.id}',
            HintKind.bigExpense,
            tr('Ungewöhnlich hohe Ausgabe'),
            tr('{x}: {y}, sonst meist {z}. Alles richtig so?',
                {'x': t.note ?? tr(t.category), 'y': Money.format(t.amountCents), 'z': Money.format(median)}),
            HintTarget.transactions));
      }
    }

    // Monday: what this week may cost, from what is free until month end
    final free = freeCents;
    if (today.weekday == DateTime.monday && free != null && free > 0) {
      final daysLeft = DateTime(today.year, today.month + 1, 0).day - today.day + 1;
      final week = (free * (daysLeft < 7 ? daysLeft : 7) / daysLeft).round();
      final weekNo = ((today.difference(DateTime(today.year)).inDays) ~/ 7) + 1;
      out.add(Hint(
          'week-${today.year}-$weekNo',
          HintKind.weekPlan,
          tr('Deine Woche: {x} frei', {'x': Money.format(week)}),
          tr('Bis Monatsende sind {x} frei, für diese Woche also etwa {y}.', {'x': Money.format(free), 'y': Money.format(week)}),
          HintTarget.buddy,
          question: tr('Plan meine Woche: Wie viel kann ich bis Sonntag ausgeben und worauf sollte ich achten?')));
    }

    // charged twice: same merchant, same amount, within three days
    for (final d in Oddities.doubles(tx, now: today, days: 10)) {
      out.add(Hint(
          'double-${d.second.id}',
          HintKind.doubleCharge,
          tr('{x} zweimal abgebucht?', {'x': d.merchant}),
          _sameDay(d.first.date, d.second.date)
              ? tr('{x} zweimal am {y}. War das zweimal gewollt?',
                  {'x': Money.format(d.cents), 'y': Dates.dayMonth(d.first.date)})
              : tr('{x} am {y} und am {z}. War das zweimal gewollt?',
                  {'x': Money.format(d.cents), 'y': Dates.dayMonth(d.first.date), 'z': Dates.dayMonth(d.second.date)}),
          HintTarget.buddy,
          question: tr('{x} hat zweimal {y} abgebucht. Was mache ich, wenn das ein Fehler war?',
              {'x': d.merchant, 'y': Money.format(d.cents)})));
    }

    // bank fees that add up over a year (shown once a month)
    final fees = Oddities.fees(tx, now: today);
    final perYear = Oddities.yearly(fees);
    if (perYear >= 3000) {
      out.add(Hint(
          'fees-$month',
          HintKind.bankFees,
          tr('Bankgebühren: rund {x} im Jahr', {'x': Money.format(perYear)}),
          fees.any((f) => f.kind == 'dispo')
              ? tr('Dabei sind Dispozinsen. Die sind meist der teuerste Kredit, den es gibt.')
              : tr('Viele Banken haben ein kostenloses Girokonto. Buddy rechnet mit dir nach.'),
          HintTarget.buddy,
          question: tr('Ich zahle rund {x} Bankgebühren im Jahr. Wie bekomme ich das runter?', {'x': Money.format(perYear)})));
    }

    // the free trial ends soon and nothing is cancelled
    final sub = subscription;
    if (sub != null && !sub.cancelled && sub.inTrial(today)) {
      final d = _daysBetween(today, sub.trialEnds);
      if (d <= 2) {
        out.add(Hint(
            'trial-${sub.trialEnds.toIso8601String().substring(0, 10)}',
            HintKind.trialEnds,
            'Dein Gratis-Test endet ${_inDays(d)}',
            tr('Danach {x} {y}. Wenn du nicht weitermachen willst, kündige vorher.', {'x': Money.format(sub.priceCents), 'y': sub.plan == PlusPlan.yearly ? tr('im Jahr') : tr('im Monat')}),
            HintTarget.subscription,
            urgent: true));
      }
    }

    // PSD2 consents run out after 90-180 days
    if (bankValidUntil != null) {
      final d = _daysBetween(today, bankValidUntil);
      if (d <= 7) {
        out.add(Hint(
            'bank-${bankValidUntil.toIso8601String().substring(0, 10)}',
            HintKind.bankExpires,
            d < 0 ? tr('Bankverbindung abgelaufen') : tr('Bankverbindung läuft {x} ab', {'x': _inDays(d)}),
            tr('Einmal kurz bestätigen, dann kommen deine Umsätze weiter automatisch.'),
            HintTarget.connections,
            urgent: d < 0));
      }
    }

    // a goal that is reached: worth a moment, and the question what comes next
    for (final g in goals) {
      if (!g.reached) continue;
      out.add(Hint('goal-done-${g.id}', HintKind.goalReached, tr('{x} {y} ist erreicht', {'x': g.emoji, 'y': g.name}),
          tr('{x} zusammen. Stark. Was wird das nächste Ziel?', {'x': Money.format(g.targetCents)}), HintTarget.buddy,
          question: tr('Ich habe mein Sparziel {x} erreicht. Was wäre ein gutes nächstes Ziel?', {'x': g.name})));
    }

    // a goal with a date that falls behind its pace: still time to catch up
    for (final g in goals) {
      final d = g.deadline;
      if (d == null || g.reached || g.targetCents <= 0) continue;
      final total = _daysBetween(g.createdAt, d), gone = _daysBetween(g.createdAt, today), left = _daysBetween(today, d);
      if (total < 60 || gone < 30 || left <= 30) continue;
      final expected = g.targetCents * gone ~/ total;
      if (g.savedCents >= expected * 0.8) continue;
      final months = (left / 30.4).ceil();
      final perMonth = (g.targetCents - g.savedCents) ~/ months;
      out.add(Hint(
          'goal-behind-${g.id}-$month',
          HintKind.goalBehind,
          tr('{x} {y} hängt hinterher', {'x': g.emoji, 'y': g.name}),
          tr('Nach Plan wären jetzt etwa {x} zusammen, es sind {y}. Mit {z} im Monat schaffst du es noch.',
              {'x': Money.format(expected), 'y': Money.format(g.savedCents), 'z': Money.format(perMonth)}),
          HintTarget.buddy,
          question: tr('Mein Sparziel {x} hängt hinterher. Wie hole ich auf, ohne dass es weh tut?', {'x': g.name})));
    }

    // goals with a date in the next 30 days that are not reached
    for (final g in goals) {
      final d = g.deadline;
      if (d == null || g.reached) continue;
      final left = _daysBetween(today, d);
      if (left >= 0 && left <= 30) {
        out.add(Hint(
            'goal-${g.id}-$month',
            HintKind.goalDue,
            tr('{x} {y}: noch {z}', {'x': g.emoji, 'y': g.name, 'z': _inDays(left)}),
            'Es fehlen ${Money.format(g.remainingCents)}. Ein kleiner Endspurt?',
            HintTarget.goals));
      }
    }

    // what the others added in shared groups, one hint per group
    final byGroup = <String, List<({String group, String groupId, String title, int cents, String by})>>{};
    for (final n in splitNews) {
      byGroup.putIfAbsent(n.groupId, () => []).add(n);
    }
    for (final list in byGroup.values) {
      final first = list.first;
      out.add(Hint(
          'split-${first.groupId}-${list.length}-${first.title}',
          HintKind.splitNew,
          tr('Neu in {x}', {'x': first.group}),
          list.length == 1
              ? tr('{x}, {y} von {z}', {'x': first.title, 'y': Money.format(first.cents), 'z': first.by})
              : tr('{x} neue Ausgaben, zuletzt {y} von {z}', {'x': list.length, 'y': list.last.title, 'z': list.last.by}),
          HintTarget.splits));
    }

    // stable: equal weights keep the order they were found in
    final order = {for (var i = 0; i < out.length; i++) out[i]: i};
    out.sort((a, b) {
      final w = b.weight.compareTo(a.weight);
      return w != 0 ? w : order[a]!.compareTo(order[b]!);
    });
    return out;
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}
