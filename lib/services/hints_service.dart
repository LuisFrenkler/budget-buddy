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

enum HintKind {
  budgetOver,
  budgetClose,
  priceUp,
  upcoming,
  trialEnds,
  bankExpires,
  bigExpense,
  goalDue,
  stillCharging,
  splitNew,
  salaryIn,
  monthReview,
  lowMonth,
  goalReached,
  goalBehind,
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
}

class HintsService {
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
      now: now,
    ).where((h) => !hidden.contains(h.id)).toList();
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
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final month = '${today.year}-${today.month}';
    final out = <Hint>[];

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

    out.sort((a, b) => (b.urgent ? 1 : 0) - (a.urgent ? 1 : 0));
    return out;
  }
}
