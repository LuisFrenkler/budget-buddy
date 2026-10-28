// When money actually lands on a goal's pot (bank sync or Umbuchung), count it
// toward the goal — so the user does the Überweisung once at the bank and the
// app follows. Bookings already applied via GoalMove are skipped via creditedIds.
import '../models/goal.dart';
import '../models/transaction.dart';
import '../utils/theme.dart';
import 'db.dart';
import 'goal_move.dart';
import 'goals_service.dart';
import 'money_accounts.dart';

class GoalCredit {
  static final _transferish = RegExp(
    r'umbuchung|übertrag|uebertrag|sparziel|tagesgeld|festgeld|pocket|eigenes konto|sparkonto|flexgeld|vertraulich',
    caseSensitive: false,
  );

  // credits new inbound pot bookings; returns cents added across all goals
  static Future<int> run({List<Transaction>? tx}) async {
    if (!MoneyAccounts.several) return 0;
    final bookings = tx ?? DB.getTx();
    var total = 0;
    for (final g in GoalsService.all()) {
      if (g.reached) continue;
      final pot = GoalMove.potOf(g);
      if (pot == null) continue;
      final potKey = pot.isMain ? null : pot.id;
      final done = g.creditedIds.toSet();
      var added = 0;
      final fresh = <String>[];
      for (final t in bookings) {
        if (done.contains(t.id) || fresh.contains(t.id)) continue;
        if (!_inbound(t, potKey)) continue;
        if (t.date.isBefore(DateTime(g.createdAt.year, g.createdAt.month, g.createdAt.day))) continue;
        if (!_counts(t, g)) continue;
        // one booking → at most one open goal on this pot (name match wins)
        if (!_owns(g, t, pot.id)) continue;
        final room = g.targetCents - g.savedCents - added;
        if (room <= 0) break;
        final piece = t.amountCents.clamp(0, room);
        if (piece <= 0) continue;
        added += piece;
        fresh.add(t.id);
      }
      if (added == 0) continue;
      g.savedCents += added;
      g.potId ??= pot.id;
      g.creditedIds = [...g.creditedIds, ...fresh];
      if (g.creditedIds.length > 400) {
        g.creditedIds = g.creditedIds.sublist(g.creditedIds.length - 400);
      }
      await GoalsService.save(g);
      total += added;
    }
    return total;
  }

  static bool _inbound(Transaction t, String? potId) {
    if (!t.isIncome || t.isRefund) return false;
    final acc = t.accountId;
    if (potId == null) return acc == null;
    return acc == potId;
  }

  static bool _counts(Transaction t, Goal g) {
    if (t.category == Categories.transfer) return true;
    final n = t.note ?? '';
    if (_transferish.hasMatch(n)) return true;
    if (n.toLowerCase().contains(g.name.toLowerCase())) return true;
    return false;
  }

  // prefer the goal named in the note; otherwise the only open goal on that pot
  static bool _owns(Goal g, Transaction t, String potId) {
    final n = (t.note ?? '').toLowerCase();
    final named = GoalsService.all().where((x) {
      if (x.reached) return false;
      final p = GoalMove.potOf(x);
      return p?.id == potId && n.contains(x.name.toLowerCase());
    }).toList();
    if (named.isNotEmpty) return named.first.id == g.id;
    final open = GoalsService.all().where((x) {
      if (x.reached) return false;
      return GoalMove.potOf(x)?.id == potId;
    }).toList();
    if (open.length == 1) return open.first.id == g.id;
    // several goals, no name in note: do not guess
    return false;
  }
}
