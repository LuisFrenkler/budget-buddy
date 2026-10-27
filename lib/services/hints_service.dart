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

enum HintKind { budgetOver, budgetClose, priceUp, upcoming, trialEnds, bankExpires, bigExpense, goalDue, stillCharging, splitNew }

// where tapping a hint leads
enum HintTarget { budgets, contracts, subscription, connections, transactions, goals, splits }

class Hint {
  final String id;
  final HintKind kind;
  final String title;
  final String text;
  final HintTarget target;
  final bool urgent;

  const Hint(this.id, this.kind, this.title, this.text, this.target, {this.urgent = false});
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
      now: now,
    ).where((h) => !hidden.contains(h.id)).toList();
  }

  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime(b.year, b.month, b.day).difference(DateTime(a.year, a.month, a.day)).inDays;

  static String _inDays(int d) => d <= 0 ? 'heute' : d == 1 ? 'morgen' : 'in $d Tagen';

  // all hints for the data, most urgent first
  static List<Hint> build({
    required List<Transaction> tx,
    required List<Budget> budgets,
    required List<Goal> goals,
    Subscription? subscription,
    DateTime? bankValidUntil,
    Map<String, DateTime> cancellations = const {},
    List<({String group, String groupId, String title, int cents, String by})> splitNews = const [],
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
        out.add(Hint('budget-over-${b.category}-$month', HintKind.budgetOver, '${b.category}: Budget überschritten',
            '${Money.format(b.spentCents - b.limitCents)} drüber. Vielleicht das Limit anpassen?', HintTarget.budgets,
            urgent: true));
      } else if (share >= 0.85 && daysLeft >= 3) {
        out.add(Hint(
            'budget-close-${b.category}-$month',
            HintKind.budgetClose,
            '${b.category}: ${(share * 100).round()} % weg',
            'Noch ${Money.format(b.limitCents - b.spentCents)} für $daysLeft Tage, also etwa '
                '${Money.format((b.limitCents - b.spentCents) ~/ daysLeft)} am Tag.',
            HintTarget.budgets));
      }
    }

    final contracts = Contracts.detect(tx, now: today);
    for (final c in contracts) {
      // cancelled, but the money still goes out
      final sent = cancellations[c.name.toLowerCase().trim()];
      if (sent != null && CancellationService.stillCharging(c, sent)) {
        out.add(Hint(
            'still-${c.name}-${c.last.date.toIso8601String().substring(0, 10)}',
            HintKind.stillCharging,
            '${c.name} bucht trotz Kündigung ab',
            'Du hast am ${Dates.dayMonth(sent)} gekündigt, am ${Dates.dayMonth(c.last.date)} kamen trotzdem '
                '${Money.format(c.monthlyCents)}. Fordere das Geld zurück; eine Lastschrift kannst du 8 Wochen '
                'lang bei deiner Bank zurückgeben.',
            HintTarget.contracts,
            urgent: true));
      }
      // a price rise in the last six weeks
      if (c.priceChange > 0 && _daysBetween(c.last.date, today) <= 42) {
        out.add(Hint(
            'price-${c.name}-${c.last.date.toIso8601String().substring(0, 10)}',
            HintKind.priceUp,
            '${c.name} ist teurer geworden',
            '+${Money.format(c.priceChange)} im Monat, jetzt ${Money.format(c.monthlyCents)}. '
                'Aufs Jahr sind das ${Money.format(c.priceChange * 12)} mehr.',
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
            '${Money.format(c.monthlyCents)} werden voraussichtlich am ${Dates.dayMonth(c.nextDate)} abgebucht.',
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
            'Ungewöhnlich hohe Ausgabe',
            '${t.note ?? t.category}: ${Money.format(t.amountCents)}, sonst meist ${Money.format(median)}. '
                'Alles richtig so?',
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
            'Danach ${Money.format(sub.priceCents)} ${sub.plan == PlusPlan.yearly ? 'im Jahr' : 'im Monat'}. '
                'Wenn du nicht weitermachen willst, kündige vorher.',
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
            d < 0 ? 'Bankverbindung abgelaufen' : 'Bankverbindung läuft ${_inDays(d)} ab',
            'Einmal kurz bestätigen, dann kommen deine Umsätze weiter automatisch.',
            HintTarget.connections,
            urgent: d < 0));
      }
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
            '${g.emoji} ${g.name}: noch ${_inDays(left)}',
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
          'Neu in ${first.group}',
          list.length == 1
              ? '${first.title}, ${Money.format(first.cents)} von ${first.by}'
              : '${list.length} neue Ausgaben, zuletzt ${list.last.title} von ${list.last.by}',
          HintTarget.splits));
    }

    out.sort((a, b) => (b.urgent ? 1 : 0) - (a.urgent ? 1 : 0));
    return out;
  }
}
