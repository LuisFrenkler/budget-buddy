// Puts money toward a goal the smart way: Umbuchung onto a savings account
// (so Konten change) and bump the goal counter. Without a second account the
// counter still moves — but nothing hits the books.
import 'package:uuid/uuid.dart';
import '../models/goal.dart';
import '../models/money_account.dart';
import '../models/transaction.dart';
import '../utils/theme.dart';
import 'db.dart';
import 'goals_service.dart';
import 'money_accounts.dart';

class GoalMoveResult {
  final int moved;
  final List<String> txIds;
  final bool booked; // true when Konten were updated
  final String? potName;
  const GoalMoveResult({required this.moved, required this.txIds, required this.booked, this.potName});
}

class GoalMove {
  static MoneyAccount? potOf(Goal g) {
    final linked = MoneyAccounts.byId(g.potId);
    if (linked != null) return linked;
    for (final a in MoneyAccounts.all) {
      if (a.kind == 'spar') return a;
    }
    return MoneyAccounts.several ? MoneyAccounts.others.first : null;
  }

  static MoneyAccount sourceOf(MoneyAccount pot) {
    if (!pot.isMain) return MoneyAccounts.main;
    for (final a in MoneyAccounts.others) {
      if (a.id != pot.id) return a;
    }
    return MoneyAccounts.main;
  }

  // [take] = back from the pot onto the source account
  static Future<GoalMoveResult> apply({
    required Goal goal,
    required int cents,
    required bool take,
    MoneyAccount? from,
    MoneyAccount? to,
  }) async {
    final room = take ? goal.savedCents : goal.remainingCents;
    final moved = cents.clamp(0, room);
    if (moved <= 0) {
      return const GoalMoveResult(moved: 0, txIds: [], booked: false);
    }

    final pot = to ?? potOf(goal);
    final source = from ?? (pot != null ? sourceOf(pot) : null);
    final txIds = <String>[];
    var booked = false;

    if (pot != null && source != null && pot.id != source.id && MoneyAccounts.several) {
      final out = take ? pot : source;
      final into = take ? source : pot;
      final id = const Uuid().v4();
      String? acc(MoneyAccount a) => a.isMain ? null : a.id;
      final label = goal.name;
      final pair = [
        Transaction(
          id: '${id}_out',
          amountCents: moved,
          category: Categories.transfer,
          date: DateTime.now(),
          isIncome: false,
          note: take ? 'Aus Sparziel $label' : 'Sparziel $label',
          accountId: acc(out),
        ),
        Transaction(
          id: '${id}_in',
          amountCents: moved,
          category: Categories.transfer,
          date: DateTime.now(),
          isIncome: true,
          note: take ? 'Zurück von Sparziel $label' : 'Für Sparziel $label',
          accountId: acc(into),
        ),
      ];
      for (final t in pair) {
        await DB.addTx(t);
        txIds.add(t.id);
      }
      booked = true;
      goal.potId ??= pot.id;
      // inbound pot leg is already in savedCents below — mark so GoalCredit skips it
      final inbound = take ? pair.first.id : pair.last.id;
      if (!take) goal.creditedIds = [...goal.creditedIds, inbound];
    }

    goal.savedCents = take ? goal.savedCents - moved : goal.savedCents + moved;
    await GoalsService.save(goal);
    return GoalMoveResult(moved: moved, txIds: txIds, booked: booked, potName: pot?.name);
  }

  static Future<void> undo(Goal goal, int savedBefore, List<String> txIds) async {
    goal.savedCents = savedBefore;
    goal.creditedIds = [for (final id in goal.creditedIds) if (!txIds.contains(id)) id];
    await GoalsService.save(goal);
    for (final id in txIds) {
      await DB.deleteTx(id);
    }
  }
}
