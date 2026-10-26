// Saving on autopilot for goals. BudgetBuddy does not move money; the goal
// counts what the user sets aside, and the app says so wherever it is set up.
//
// - monthly: on the first app start of a month the fixed amount is added
//   (once per month, missed months are not added up, so nobody is surprised)
// - round-up: each expense since switching it on is rounded up to the full
//   euro, the difference goes to the goal (3,20 € -> 0,80 €)
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/goal.dart';
import '../models/transaction.dart';
import 'db.dart';
import 'goals_service.dart';
import 'plus_service.dart';

class AutoSave {
  static String _month(DateTime d) => '${d.year}-${d.month}';

  // the cents a booking contributes when rounded up
  static int roundUpOf(int cents) => cents % 100 == 0 ? 0 : 100 - cents % 100;

  // applies both rules to one goal; returns the cents added
  static int apply(Goal g, List<Transaction> tx, DateTime now) {
    if (g.reached) return 0;
    var added = 0;
    if (g.monthlyCents > 0 && g.lastMonthly != _month(now)) {
      added += g.monthlyCents;
      g.lastMonthly = _month(now);
    }
    if (g.roundUp && g.roundUpSince != null) {
      final since = DateTime(g.roundUpSince!.year, g.roundUpSince!.month, g.roundUpSince!.day);
      final done = g.roundedIds.toSet();
      for (final t in tx) {
        if (t.isIncome || t.date.isBefore(since) || done.contains(t.id)) continue;
        added += roundUpOf(t.amountCents);
        g.roundedIds.add(t.id);
      }
      // keep the list short: old bookings are behind "since" anyway
      if (g.roundedIds.length > 500) g.roundedIds.removeRange(0, g.roundedIds.length - 500);
    }
    // never past the target
    final room = g.targetCents - g.savedCents;
    if (added > room) added = room;
    g.savedCents += added;
    return added;
  }

  // what rounding up would have brought in the last 30 days
  static int roundUpEstimate(List<Transaction> tx, DateTime now) {
    final from = now.subtract(const Duration(days: 30));
    return tx
        .where((t) => !t.isIncome && !t.date.isBefore(from))
        .fold<int>(0, (s, t) => s + roundUpOf(t.amountCents));
  }

  static Timer? _debounce;

  // a goal the autopilot just completed, for the celebration on screen
  static final reached = ValueNotifier<Goal?>(null);

  // after new bookings: round them up a moment later, once
  static void runSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), run);
  }

  // runs over all goals and saves the changed ones; returns the total added
  static Future<int> run({DateTime? now}) async {
    // the autopilot is part of Plus: without it, goals keep what they have
    // and the automation waits until Plus is back
    if (!PlusService.active.value) return 0;
    final today = now ?? DateTime.now();
    final tx = DB.getTx();
    var total = 0;
    for (final g in GoalsService.all()) {
      if (!g.automated) continue;
      final before = g.toMap().toString();
      final wasReached = g.reached;
      total += apply(g, tx, today);
      if (!wasReached && g.reached) reached.value = g;
      if (g.toMap().toString() != before) await GoalsService.save(g);
    }
    return total;
  }
}
