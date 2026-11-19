// The money check before sign-up: a guest's bank bookings, in memory only.
// The ledger is wiped for guests, and nothing of a statement is stored before
// there is an account to store it in. After sign-up the same bookings go into
// the ledger, so the feed shows the same finds.
import '../models/transaction.dart';
import 'ahead_agent.dart';
import 'db.dart';
import 'hints_service.dart';

class GuestMoneyCheck {
  static List<Transaction> _tx = const [];

  static List<Transaction> get tx => _tx;

  // a file was read, even when nothing was found in it
  static bool get done => _tx.isNotEmpty;

  static void set(List<Transaction> tx) => _tx = tx;

  // another account signs in on this device: the guest's bookings are not theirs
  static void clear() => _tx = const [];

  // subscriptions, contracts, double charges and fees in the bookings; taxes come from the three answers
  static List<AgentFind> finds({DateTime? now}) {
    if (_tx.isEmpty) return const [];
    final hints = HintsService.current(tx: _tx, budgets: const [], goals: const [], now: now);
    return AheadAgent.run(tx: _tx, hints: hints, now: now).where((f) => f.kind == FindKind.money).toList();
  }

  // the new account starts with the bookings the person already showed Ahead
  static Future<int> adopt() async {
    final mine = _tx;
    _tx = const [];
    for (final t in mine) {
      await DB.addTx(t);
    }
    if (mine.isNotEmpty) AheadAgent.changed.value++;
    return mine.length;
  }
}
